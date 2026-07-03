// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation
import SwiftUI

/// The four Tailwind "Oatmeal" neutral ramps (mauve / olive / mist / taupe),
/// stored as the exact oklch scales promoted into Tailwind CSS v4.3 core. Each
/// entry is (L 0…1, C, H°) for shades 50, 100, 200, 300, 400, 500, 600, 700,
/// 800, 900, 950 — converted to sRGB at build-of-view time by `Color(oklchL:c:h:)`.
enum Palette: String, CaseIterable, Identifiable {
    case mauve, olive, mist, taupe

    var id: String { rawValue }

    /// Display name (the rawValue stays mauve/olive/mist/taupe for stable persistence).
    var label: String {
        switch self {
        case .mauve: return "Lavender"
        case .olive: return "Dark Olive"
        case .mist: return "Sea Grey"
        case .taupe: return "Brown Olive"
        }
    }

    var ramp: [(l: Double, c: Double, h: Double)] {
        switch self {
        case .mauve:
            return [(0.985, 0, 0), (0.96, 0.003, 325.6), (0.922, 0.005, 325.62),
                    (0.865, 0.012, 325.68), (0.711, 0.019, 323.02), (0.542, 0.034, 322.5),
                    (0.435, 0.029, 321.78), (0.364, 0.029, 323.89), (0.263, 0.024, 320.12),
                    (0.212, 0.019, 322.12), (0.145, 0.008, 326)]
        case .olive:
            return [(0.988, 0.003, 106.5), (0.966, 0.005, 106.5), (0.93, 0.007, 106.5),
                    (0.88, 0.011, 106.6), (0.737, 0.021, 106.9), (0.58, 0.031, 107.3),
                    (0.466, 0.025, 107.3), (0.394, 0.023, 107.4), (0.286, 0.016, 107.4),
                    (0.228, 0.013, 107.4), (0.153, 0.006, 107.1)]
        case .mist:
            return [(0.987, 0.002, 197.1), (0.963, 0.002, 197.1), (0.925, 0.005, 214.3),
                    (0.872, 0.007, 219.6), (0.723, 0.014, 214.4), (0.56, 0.021, 213.5),
                    (0.45, 0.017, 213.2), (0.378, 0.015, 216), (0.275, 0.011, 216.9),
                    (0.218, 0.008, 223.9), (0.148, 0.004, 228.8)]
        case .taupe:
            return [(0.986, 0.002, 67.8), (0.96, 0.002, 17.2), (0.922, 0.005, 34.3),
                    (0.868, 0.007, 39.5), (0.714, 0.014, 41.2), (0.547, 0.021, 43.1),
                    (0.438, 0.017, 39.3), (0.367, 0.016, 35.7), (0.268, 0.011, 36.5),
                    (0.214, 0.009, 43.1), (0.147, 0.004, 49.3)]
        }
    }
}

/// Appearance preference (SPEC §9 + user request): follow the OS so the panel
/// slips into dark in the evening, or pin one appearance.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match macOS"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil = follow the system; otherwise force the scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Resolved semantic colours for one palette in one appearance. Mirrors the
/// token mapping used in the design concept: the accent is a deeper shade of the
/// *same* ramp, so nothing shouts.
struct Theme {
    let palette: Palette
    let isDark: Bool
    private let ramp: [Color]

    init(palette: Palette, scheme: ColorScheme) {
        self.palette = palette
        self.isDark = (scheme == .dark)
        self.ramp = palette.ramp.map { Color(oklchL: $0.l, c: $0.c, h: $0.h) }
    }

    /// Shade by Tailwind step: 50→0, 100→1, … 950→10.
    private func c(_ i: Int) -> Color { ramp[i] }

    var ground: Color { isDark ? c(10) : c(1) }       // window / desktop behind
    var panel: Color { isDark ? c(9) : c(0) }         // primary surface
    var inset: Color { isDark ? c(8) : c(1) }         // recessed fields, chips
    var ink: Color { isDark ? c(0) : c(10) }          // primary text
    var inkSoft: Color { isDark ? c(3) : c(6) }       // secondary text
    var inkFaint: Color { isDark ? c(5) : c(4) }      // captions, disabled
    var line: Color { isDark ? c(8) : c(2) }          // hairline dividers
    var lineStrong: Color { isDark ? c(7) : c(3) }    // control borders
    var track: Color { isDark ? c(8) : c(2) }         // fader groove
    var accent: Color { isDark ? c(3) : c(7) }        // fills, primary button
    var accent2: Color { isDark ? c(4) : c(6) }       // accent text
    var accentInk: Color { isDark ? c(10) : c(0) }    // text on accent
    var knob: Color { isDark ? c(7) : c(0) }          // fader knob face
    var knobLine: Color { isDark ? c(6) : c(3) }      // fader knob edge

    /// Semantic status hues, kept low-chroma so they sit inside the calm palette.
    var on: Color { isDark ? Color(oklchL: 0.72, c: 0.11, h: 150) : Color(oklchL: 0.60, c: 0.088, h: 150) }
    var warn: Color { isDark ? Color(oklchL: 0.76, c: 0.13, h: 60) : Color(oklchL: 0.64, c: 0.13, h: 55) }
}

extension Color {
    /// Build an sRGB `Color` from an OKLCH triple (L 0…1, C, H°). Lets us keep
    /// the exact Tailwind oklch values in source and convert with Björn
    /// Ottosson's OKLab→linear-sRGB matrices, rather than pasting approximate hex.
    init(oklchL l: Double, c: Double, h: Double) {
        let hr = h * .pi / 180
        let okA = c * Foundation.cos(hr)
        let okB = c * Foundation.sin(hr)

        let l_ = l + 0.3963377774 * okA + 0.2158037573 * okB
        let m_ = l - 0.1055613458 * okA - 0.0638541728 * okB
        let s_ = l - 0.0894841775 * okA - 1.2914855480 * okB
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        let r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let b = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        func encode(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * Foundation.pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        self.init(.sRGB, red: encode(r), green: encode(g), blue: encode(b), opacity: 1)
    }
}
