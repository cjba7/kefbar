// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// Stores the pre-mute volume so `unmute` can restore it. The app keeps this in
/// memory; the CLI needs cross-process persistence because `kefbar mute` and
/// `kefbar unmute` are separate invocations (SPEC §8).
public protocol MuteStore {
    func priorVolume(id: String) -> Int?
    func setPriorVolume(_ volume: Int?, id: String)
}

/// File-backed mute state keyed by speaker id (MAC) or host, stored as a small
/// JSON map at `mute-state.json`. Atomic writes.
public final class FileMuteStore: MuteStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    public convenience init() throws {
        self.init(url: try AppSupport.muteStateURL)
    }

    private func load() -> [String: Int] {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return map
    }

    private func save(_ map: [String: Int]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func priorVolume(id: String) -> Int? {
        load()[id]
    }

    public func setPriorVolume(_ volume: Int?, id: String) {
        var map = load()
        map[id] = volume            // nil removes the key (clears on unmute)
        save(map)
    }
}
