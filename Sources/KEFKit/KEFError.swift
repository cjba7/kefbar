// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// Errors surfaced by KEFKit. The CLI maps these to exit codes (SPEC §11):
/// `unreachable`/`badResponse` -> 3, `writeUnsupported` -> 4.
public enum KEFError: Error, LocalizedError, Equatable {
    /// Transport failure — could not reach the speaker.
    case unreachable(String)
    /// Reachable, but the write was rejected on both the POST and legacy GET
    /// paths (genuinely old / unsupported firmware).
    case writeUnsupported(String)
    /// Reachable, but the response was not the expected shape.
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let m): return m
        case .writeUnsupported(let m): return m
        case .badResponse(let m): return m
        }
    }
}
