// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// Model + firmware derivation from `settings:/releasetext` (SPEC §5 refinement
/// #2). pykefcontrol derives both from this path, not from
/// `settings:/kef/host/modelName` (which returns an unfriendly board code like
/// `"SP4041"`). Example: `"LSXII_V30137"` -> model `"LSXII"`, firmware `"V30137"`.
public enum ModelInfo {
    /// Normalise raw model prefixes to canonical W2 names (mirrors pykefcontrol
    /// `_MODEL_ALIASES`). On current firmware the prefix is already canonical
    /// (e.g. `"LSXII"`), so this is a no-op there but future-proofs older strings.
    static let aliases: [String: String] = [
        "LS50W2": "LS50WII",
        "LSX2LT": "LSXIILT",
        "LSX2": "LSXII",
    ]

    public static func parseReleaseText(_ text: String) -> (model: String, firmware: String) {
        let parts = text.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        let rawModel = parts.first ?? text
        let model = aliases[rawModel] ?? rawModel
        let firmware = parts.count > 1 ? parts[1] : ""
        return (model, firmware)
    }
}
