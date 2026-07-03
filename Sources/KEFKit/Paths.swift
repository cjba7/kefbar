// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// KEF W2 HTTP API paths (authoritative — verified live against an LSX II and
/// against pykefcontrol; see SPEC.md §5).
public enum KEFPath {
    /// Volume, `i32_` 0...100 (0 == muted). Primary control.
    public static let volume = "player:volume"
    /// Power status, value under `kefSpeakerStatus`: `powerOn` | `standby`.
    public static let speakerStatus = "settings:/kef/host/speakerStatus"
    /// Physical source, value under `kefPhysicalSource` (display only in v1).
    public static let physicalSource = "settings:/kef/play/physicalSource"
    /// MAC address, `string_` — stable identity key.
    public static let primaryMacAddress = "settings:/system/primaryMacAddress"
    /// User-facing device name, `string_`.
    public static let deviceName = "settings:/deviceName"
    /// Max volume, `i32_` — clamp slider/CLI to this.
    public static let maximumVolume = "settings:/kef/host/maximumVolume"
    /// Release text, `string_` e.g. `"LSXII_V30137"` — source of model + firmware.
    public static let releaseText = "settings:/releasetext"
}

/// Locations under `~/Library/Application Support/kefbar/` shared by app + CLI.
public enum AppSupport {
    /// Create (if needed) and return the kefbar application-support directory.
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("kefbar", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `config.json` — single source of truth (app writes, CLI reads).
    public static var configURL: URL {
        get throws { try directory().appendingPathComponent("config.json") }
    }

    /// `cli.lock` — flock target serialising relative up/down (SPEC §10).
    public static var lockURL: URL {
        get throws { try directory().appendingPathComponent("cli.lock") }
    }

    /// `mute-state.json` — pre-mute levels so unmute can restore across processes.
    public static var muteStateURL: URL {
        get throws { try directory().appendingPathComponent("mute-state.json") }
    }
}
