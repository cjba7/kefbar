// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation
import KEFKit

/// Lightweight file log (agents have nowhere to print). Set `KEFBAR_APP_LOG=1`.
enum AppLog {
    private static let enabled = ProcessInfo.processInfo.environment["KEFBAR_APP_LOG"] == "1"
    private static let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("kefbar-app.log")
    static func log(_ message: String) {
        guard enabled else { return }
        let line = "[\(Date())] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// App-wide state (SPEC §9). `@MainActor` so every `@Published` mutation, including
/// those arriving from the event-poll loop, happens on the main thread. The app owns
/// config writes (the CLI is read-only).
@MainActor
final class SpeakerStore: ObservableObject {
    @Published private(set) var speakers: [SpeakerVM] = []
    @Published private(set) var discovered: [DiscoveredSpeaker] = []
    @Published private(set) var isScanning = false

    private var config: Config

    init() {
        config = (try? Config.load()) ?? Config()
        AppLog.log("store init: \(config.speakers.count) configured speaker(s)")
        rebuild()
    }

    var cliStep: Int { config.cliStep }
    var defaultSpeakerId: String? { config.defaultSpeakerId }

    /// Reconcile the VM list with config, preserving live VMs across reloads.
    private func rebuild() {
        let existing = Dictionary(speakers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = config.speakers.map { existing[$0.id] ?? SpeakerVM(speaker: $0) }
        for vm in speakers where !config.speakers.contains(where: { $0.id == vm.id }) {
            vm.stop()  // removed speaker
        }
        speakers = next
        for vm in speakers { vm.start() }
    }

    // MARK: - Discovery

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        AppLog.log("rescan started")
        Task {
            let found = await Discovery.discover()
            self.discovered = found
            self.isScanning = false
            AppLog.log("rescan found \(found.count)")
        }
    }

    // MARK: - Config mutations (app owns writes; atomic)

    func add(_ d: DiscoveredSpeaker) {
        if let idx = config.speakers.firstIndex(where: { $0.id.caseInsensitiveCompare(d.mac) == .orderedSame }) {
            config.speakers[idx].host = d.host
            config.speakers[idx].model = d.model
            config.speakers[idx].maxVolume = d.maxVolume
            config.speakers[idx].firmware = d.firmware
        } else {
            config.speakers.append(Speaker(
                id: d.mac, name: d.name.isEmpty ? d.model : d.name, host: d.host,
                model: d.model, maxVolume: d.maxVolume, firmware: d.firmware))
        }
        if config.defaultSpeakerId == nil { config.defaultSpeakerId = d.mac }
        save()
    }

    func remove(id: String) {
        config.speakers.removeAll { $0.id == id }
        if config.defaultSpeakerId == id { config.defaultSpeakerId = config.speakers.first?.id }
        save()
    }

    func rename(id: String, to name: String) {
        guard let idx = config.speakers.firstIndex(where: { $0.id == id }),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        config.speakers[idx].name = name
        save()
    }

    func setHost(id: String, host: String) {
        guard let idx = config.speakers.firstIndex(where: { $0.id == id }),
              !host.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        config.speakers[idx].host = host
        save()
    }

    func setDefault(id: String) { config.defaultSpeakerId = id; save() }

    func setCliStep(_ step: Int) { config.cliStep = min(10, max(1, step)); save() }

    private func save() {
        do { try config.save() } catch { AppLog.log("save failed: \(error)") }
        rebuild()
    }
}

/// Observable view-model for one speaker: holds live volume/power/mute and drives the
/// KEF client (throttled writes, event-poll live updates).
@MainActor
final class SpeakerVM: ObservableObject, Identifiable {
    nonisolated let id: String
    let name: String
    let host: String
    let model: String
    let maxVolume: Int

    @Published var volume: Double = 0
    @Published var power: String = ""       // "powerOn" | "standby" | "" (unknown)
    @Published var muted = false
    @Published var reachable = true

    private let client: KEFClient
    private var started = false
    private var eventTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var lastWriteAt = Date.distantPast
    private var suppressEchoUntil = Date.distantPast
    private var priorVolume = 15

    init(speaker: Speaker) {
        id = speaker.id
        name = speaker.name
        host = speaker.host
        model = speaker.model ?? ""
        maxVolume = speaker.maxVolume
        client = KEFClient(host: speaker.host)
    }

    var isOn: Bool { power == "powerOn" }
    var isStandby: Bool { power == "standby" }

    func start() {
        guard !started else { return }
        started = true
        Task { await refresh() }
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.client.events() { self.apply(event) }
        }
    }

    func stop() {
        eventTask?.cancel(); eventTask = nil
        writeTask?.cancel(); writeTask = nil
        started = false
    }

    private func refresh() async {
        do {
            let v = try await client.volume()
            volume = Double(v)
            muted = (v == 0)
            reachable = true
            AppLog.log("\(name): volume=\(v)")
        } catch {
            reachable = false
            AppLog.log("\(name): unreachable (\(error))")
        }
        if let s = try? await client.status() { power = s }
    }

    private func apply(_ event: SpeakerEvent) {
        switch event {
        case .volume(let v):
            if Date() < suppressEchoUntil { return }  // don't let remote-echo fight a live drag
            volume = Double(v)
            muted = (v == 0)
            AppLog.log("\(name): live event volume=\(v)")
        case .status(let s):
            power = s
            AppLog.log("\(name): live event status=\(s)")
        }
    }

    /// Called continuously while dragging. Throttles writes to ~10/s and always sends
    /// the final value on release (SPEC §9).
    func onSlider(_ newValue: Double) {
        volume = newValue
        suppressEchoUntil = Date().addingTimeInterval(0.6)
        let target = Int(newValue.rounded())
        writeTask?.cancel()
        let delay = max(0, 0.1 - Date().timeIntervalSince(lastWriteAt))
        writeTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            self.lastWriteAt = Date()
            _ = try? await self.client.setVolume(target)
        }
    }

    func toggleMute() {
        Task { [weak self] in
            guard let self else { return }
            if self.muted || Int(self.volume) == 0 {
                let restore = self.priorVolume > 0 ? self.priorVolume : 15
                self.suppressEchoUntil = Date().addingTimeInterval(0.6)
                _ = try? await self.client.setVolume(restore)
                self.volume = Double(restore); self.muted = false
            } else {
                self.priorVolume = Int(self.volume.rounded())
                self.suppressEchoUntil = Date().addingTimeInterval(0.6)
                _ = try? await self.client.setVolume(0)
                self.volume = 0; self.muted = true
            }
        }
    }
}
