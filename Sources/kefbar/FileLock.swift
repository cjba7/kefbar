// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Darwin
import Foundation

/// Exclusive advisory file lock via `flock(2)` (SPEC §10). Serialises relative
/// up/down read-modify-write so N rapid taps sum correctly instead of racing on
/// the same base value.
final class FileLock {
    private let fd: Int32

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fd = open(url.path, O_CREAT | O_RDWR, mode_t(0o644))
        if fd < 0 {
            throw CLIError.usage("cannot open lock file at \(url.path)")
        }
    }

    /// Block until the exclusive lock is held (briefly, if another tap holds it).
    func lock() { _ = flock(fd, LOCK_EX) }

    func unlock() { _ = flock(fd, LOCK_UN) }

    deinit { close(fd) }
}
