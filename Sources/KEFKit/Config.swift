// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// A configured speaker (SPEC §7). Keyed by MAC so DHCP IP changes self-heal.
public struct Speaker: Codable, Equatable {
    public var id: String            // MAC — stable key
    public var name: String
    public var host: String
    public var model: String?
    public var maxVolume: Int
    public var firmware: String?
    public var lastSeen: String?

    public init(id: String, name: String, host: String, model: String? = nil,
                maxVolume: Int = 100, firmware: String? = nil, lastSeen: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.model = model
        self.maxVolume = maxVolume
        self.firmware = firmware
        self.lastSeen = lastSeen
    }
}

/// The shared config file model (SPEC §7). App owns writes; CLI is read-only.
public struct Config: Codable, Equatable {
    public var version: Int
    public var defaultSpeakerId: String?
    public var cliStep: Int
    public var speakers: [Speaker]

    public init(version: Int = 1, defaultSpeakerId: String? = nil,
                cliStep: Int = 5, speakers: [Speaker] = []) {
        self.version = version
        self.defaultSpeakerId = defaultSpeakerId
        self.cliStep = cliStep
        self.speakers = speakers
    }

    // Lenient decoding: tolerate a hand-edited file missing version/cliStep/speakers.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        defaultSpeakerId = try c.decodeIfPresent(String.self, forKey: .defaultSpeakerId)
        cliStep = try c.decodeIfPresent(Int.self, forKey: .cliStep) ?? 5
        speakers = try c.decodeIfPresent([Speaker].self, forKey: .speakers) ?? []
    }

    // MARK: - Lookups

    public func speaker(named name: String) -> Speaker? {
        speakers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func speaker(id: String) -> Speaker? {
        speakers.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    public var defaultSpeaker: Speaker? {
        guard let id = defaultSpeakerId else { return nil }
        return speaker(id: id)
    }

    // MARK: - Load / save (atomic — temp + rename via .atomic)

    public static func load(from url: URL? = nil) throws -> Config {
        let u = try (url ?? AppSupport.configURL)
        guard FileManager.default.fileExists(atPath: u.path) else {
            return Config()  // no config yet -> empty default
        }
        let data = try Data(contentsOf: u)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save(to url: URL? = nil) throws {
        let u = try (url ?? AppSupport.configURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u, options: .atomic)
    }

    // MARK: - Clamp helpers (SPEC §8)

    public static func clampVolume(_ v: Int, maxVolume: Int) -> Int {
        max(0, min(v, maxVolume))
    }

    public static func isValidStep(_ step: Int) -> Bool {
        (1...10).contains(step)
    }
}

/// Outcome of resolving which speaker a command targets.
public enum ResolvedSpeaker: Equatable {
    case adHocHost(String)     // from --host: max volume unknown until fetched
    case configured(Speaker)   // from config: name / default / sole speaker
}

/// Why resolution failed (SPEC §11 resolution rules).
public enum ResolutionError: Error, Equatable {
    case notFound(String)      // --speaker name not in config
    case noneConfigured        // no speakers and no --host
    case ambiguous([String])   // several speakers; need a selector
}

extension Config {
    /// Pure speaker-resolution matrix (SPEC §11):
    /// 1. `--host`  2. `--speaker`  3. default  4. sole speaker  5. error.
    public static func resolve(config: Config, host: String?, speakerName: String?)
        -> Result<ResolvedSpeaker, ResolutionError>
    {
        if let host, !host.isEmpty {
            return .success(.adHocHost(host))
        }
        if let name = speakerName {
            if let s = config.speaker(named: name) { return .success(.configured(s)) }
            return .failure(.notFound(name))
        }
        if let s = config.defaultSpeaker {
            return .success(.configured(s))
        }
        if config.speakers.count == 1 {
            return .success(.configured(config.speakers[0]))
        }
        if config.speakers.isEmpty {
            return .failure(.noneConfigured)
        }
        return .failure(.ambiguous(config.speakers.map(\.name)))
    }
}
