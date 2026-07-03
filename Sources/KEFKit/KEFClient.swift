// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// Result of a volume write. `usedLegacyGET` is true when the write had to fall
/// back to the GET-only path (old firmware) — the caller warns, non-blocking
/// (SPEC §5 firmware rule).
public struct WriteResult: Equatable {
    public let volume: Int
    public let usedLegacyGET: Bool
}

/// A live change delivered by the event-poll loop (SPEC §5).
public enum SpeakerEvent: Equatable {
    case volume(Int)
    case status(String)  // "powerOn" | "standby"
}

/// Async HTTP client for one KEF W2 speaker (SPEC §8). No discovery, no polling
/// here — those arrive in later milestones. Talks directly to `http://<host>`.
public final class KEFClient {
    public let host: String
    private let http: HTTP

    /// Once a write falls back to GET, remember it for this process so later
    /// writes skip the failing POST attempt.
    private var preferLegacyGET = false

    /// Separate session for long-poll requests: `pollQueue` blocks server-side for
    /// up to its timeout, so it needs a request timeout longer than the control one.
    private lazy var pollHTTP = HTTP(timeout: 65)

    public init(host: String, timeout: TimeInterval = 5.0) {
        self.host = host
        self.http = HTTP(timeout: timeout)
    }

    // MARK: - URL builders

    /// Base components for `http://<host>`. Speakers are on port 80, but a
    /// `host:port` form is accepted (handy for the mock server and tunnels).
    private func baseComponents(path: String) -> URLComponents {
        var c = URLComponents()
        c.scheme = "http"
        if let colon = host.lastIndex(of: ":"),
           let port = Int(host[host.index(after: colon)...]) {
            c.host = String(host[..<colon])
            c.port = port
        } else {
            c.host = host
        }
        c.path = path
        return c
    }

    private func getDataURL(_ path: String) -> URL {
        var c = baseComponents(path: "/api/getData")
        c.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: "value"),
        ]
        return c.url!
    }

    private var setDataURL: URL {
        baseComponents(path: "/api/setData").url!
    }

    private func setDataGETURL(path: String, valueJSON: String) -> URL {
        var c = baseComponents(path: "/api/setData")
        c.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: "value"),
            URLQueryItem(name: "value", value: valueJSON),
        ]
        return c.url!
    }

    private func ensureOK(_ r: HTTPResponse) throws {
        guard (200..<300).contains(r.status) else {
            throw KEFError.badResponse("speaker returned HTTP \(r.status)")
        }
    }

    // MARK: - Reads

    public func volume() async throws -> Int {
        let r = try await http.get(getDataURL(KEFPath.volume))
        try ensureOK(r)
        return try KEFValue.int(r.data)
    }

    public func status() async throws -> String {
        let r = try await http.get(getDataURL(KEFPath.speakerStatus))
        try ensureOK(r)
        return try KEFValue.string(r.data)
    }

    public func source() async throws -> String {
        let r = try await http.get(getDataURL(KEFPath.physicalSource))
        try ensureOK(r)
        return try KEFValue.string(r.data)
    }

    public func mac() async throws -> String {
        let r = try await http.get(getDataURL(KEFPath.primaryMacAddress))
        try ensureOK(r)
        return try KEFValue.string(r.data)
    }

    public func deviceName() async throws -> String {
        let r = try await http.get(getDataURL(KEFPath.deviceName))
        try ensureOK(r)
        return try KEFValue.string(r.data)
    }

    public func maxVolume() async throws -> Int {
        let r = try await http.get(getDataURL(KEFPath.maximumVolume))
        try ensureOK(r)
        return try KEFValue.int(r.data)
    }

    public func releaseText() async throws -> String {
        let r = try await http.get(getDataURL(KEFPath.releaseText))
        try ensureOK(r)
        return try KEFValue.string(r.data)
    }

    /// Model + firmware, both derived from `settings:/releasetext`.
    public func modelFirmware() async throws -> (model: String, firmware: String) {
        ModelInfo.parseReleaseText(try await releaseText())
    }

    // MARK: - Writes (POST, with legacy GET-only fallback)

    /// Write an absolute volume. Tries POST first (W2 firmware); on a non-2xx
    /// response falls back to the legacy GET write and flags it so the caller
    /// can warn. Transport failures -> `.unreachable`; a rejected write on both
    /// paths -> `.writeUnsupported`.
    @discardableResult
    public func setVolume(_ volume: Int) async throws -> WriteResult {
        if !preferLegacyGET {
            let r = try await http.postJSON(setDataURL, body: Self.volumeBody(volume))
            if (200..<300).contains(r.status) {
                return WriteResult(volume: volume, usedLegacyGET: false)
            }
            // Non-2xx: likely GET-only firmware — fall through to the GET write.
        }
        let r = try await http.get(
            setDataGETURL(path: KEFPath.volume, valueJSON: Self.volumeValueJSON(volume)))
        if (200..<300).contains(r.status) {
            preferLegacyGET = true
            return WriteResult(volume: volume, usedLegacyGET: true)
        }
        throw KEFError.writeUnsupported("speaker rejected the volume write (HTTP \(r.status))")
    }

    // MARK: - Mute / unmute (client-side: volume 0 with stored prior level)

    @discardableResult
    public func mute(id: String, store: MuteStore) async throws -> WriteResult {
        let current = try await volume()
        if current > 0 {
            store.setPriorVolume(current, id: id)  // don't overwrite prior if already 0
        }
        return try await setVolume(0)
    }

    @discardableResult
    public func unmute(id: String, store: MuteStore, fallback: Int, maxVolume: Int) async throws
        -> WriteResult
    {
        let target = Config.clampVolume(store.priorVolume(id: id) ?? fallback, maxVolume: maxVolume)
        let result = try await setVolume(target)
        store.setPriorVolume(nil, id: id)  // clear stored level
        return result
    }

    // MARK: - Event poll (live updates — SPEC §5)

    private var modifyQueueURL: URL { baseComponents(path: "/api/event/modifyQueue").url! }

    private func pollQueueURL(queueId: String, timeout: Int) -> URL {
        var c = baseComponents(path: "/api/event/pollQueue")
        c.queryItems = [
            URLQueryItem(name: "queueId", value: queueId),
            URLQueryItem(name: "timeout", value: String(timeout)),
        ]
        return c.url!
    }

    /// Subscribe to changes for `paths`; returns the queue id (a `{guid}` string).
    public func subscribe(paths: [String] = [KEFPath.volume, KEFPath.speakerStatus]) async throws
        -> String
    {
        let body: [String: Any] = [
            "subscribe": paths.map { ["path": $0, "type": "itemWithValue"] },
            "unsubscribe": [],
        ]
        let r = try await http.postJSON(modifyQueueURL, body: JSONSerialization.data(withJSONObject: body))
        try ensureOK(r)
        // The queue id comes back as a bare JSON string fragment, e.g. "{guid}".
        let parsed = try? JSONSerialization.jsonObject(with: r.data, options: [.fragmentsAllowed])
        if let queueId = parsed as? String { return queueId }
        if let queueId = (parsed as? [String])?.first { return queueId }  // tolerate array form too
        throw KEFError.badResponse("unexpected modifyQueue response")
    }

    /// Long-poll the queue for up to `timeout` seconds; returns any changes.
    public func poll(queueId: String, timeout: Int = 10) async throws -> [SpeakerEvent] {
        let r = try await pollHTTP.get(pollQueueURL(queueId: queueId, timeout: timeout))
        try ensureOK(r)
        return Self.parseEvents(r.data)
    }

    /// Live event stream: subscribe, then poll in a loop, re-subscribing after an
    /// error (handles poll timeouts, standby dropping the interface, reconnects).
    public func events(pollTimeout: Int = 10) -> AsyncStream<SpeakerEvent> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        let queueId = try await subscribe()
                        while !Task.isCancelled {
                            for event in try await poll(queueId: queueId, timeout: pollTimeout) {
                                continuation.yield(event)
                            }
                        }
                    } catch {
                        if Task.isCancelled { break }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)  // backoff, then re-subscribe
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parse a pollQueue response. Each element looks like
    /// `{"path":"player:volume","itemType":"update","itemValue":{"type":"i32_","i32_":35}}`;
    /// the value lives under the key named by `itemValue.type` (SPEC §5 refinement #1).
    static func parseEvents(_ data: Data) -> [SpeakerEvent] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var events: [SpeakerEvent] = []
        for item in array {
            guard let path = item["path"] as? String,
                  let value = item["itemValue"] as? [String: Any],
                  let type = value["type"] as? String
            else { continue }
            switch path {
            case KEFPath.volume:
                if let n = value[type] as? Int {
                    events.append(.volume(n))
                } else if let n = value[type] as? NSNumber {
                    events.append(.volume(n.intValue))
                }
            case KEFPath.speakerStatus:
                if let s = value[type] as? String { events.append(.status(s)) }
            default:
                break
            }
        }
        return events
    }

    // MARK: - Envelope builders (exposed for tests — SPEC §15)

    /// POST body: `{"path":"player:volume","roles":"value","value":{"type":"i32_","i32_":N}}`
    static func volumeBody(_ volume: Int) -> Data {
        let obj: [String: Any] = [
            "path": KEFPath.volume,
            "roles": "value",
            "value": ["type": "i32_", "i32_": volume],
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    /// Compact JSON for the legacy GET `value` query param.
    static func volumeValueJSON(_ volume: Int) -> String {
        let obj: [String: Any] = ["type": "i32_", "i32_": volume]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
