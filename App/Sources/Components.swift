// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import SwiftUI

/// KEF's signature Uni-Q driver seats the tweeter inside concentric rings. The
/// speaker's power state is drawn as that mark: lit when on, faint on standby,
/// warn-coloured when unreachable.
struct UniQMark: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.4).frame(width: 16, height: 16)
            Circle().strokeBorder(color, lineWidth: 1.3).frame(width: 9, height: 9)
            Circle().fill(color).frame(width: 3.6, height: 3.6)
        }
        .frame(width: 17, height: 17)
        .animation(.easeInOut(duration: 0.25), value: color)
    }
}

/// A quiet precision fader: a thin groove with an accent fill, a soft knob, and
/// a faint tick scale. Drives volume through `onChange`, which the caller wires
/// to the view-model's throttled `onSlider` (SPEC §9). Tap-to-set and drag both
/// work, plus VoiceOver / keyboard adjust.
struct VolumeFader: View {
    let value: Double
    let range: ClosedRange<Double>
    let theme: Theme
    let onChange: (Double) -> Void

    private let knob: CGFloat = 15

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat(fraction) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.track).frame(height: 5)
                    Capsule().fill(theme.accent).frame(width: max(0, x), height: 5)
                    Circle()
                        .fill(theme.knob)
                        .overlay(Circle().strokeBorder(theme.knobLine, lineWidth: 1))
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                        .offset(x: min(max(0, x - knob / 2), w - knob))
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { emit($0.location.x, w) }
                        .onEnded { emit($0.location.x, w) }
                )
            }
            .frame(height: knob)

            HStack(spacing: 0) {
                ForEach(0..<11) { i in
                    Rectangle().fill(theme.lineStrong).frame(width: 1, height: i % 2 == 0 ? 5 : 3)
                    if i < 10 { Spacer(minLength: 0) }
                }
            }
            .frame(height: 5)
            .opacity(0.55)
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(range.upperBound, value + 1))
            case .decrement: onChange(max(range.lowerBound, value - 1))
            @unknown default: break
            }
        }
    }

    private func emit(_ x: CGFloat, _ w: CGFloat) {
        guard w > 0 else { return }
        let f = min(1, max(0, Double(x / w)))
        onChange((range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded())
    }
}

/// A calm text button that warms its background on hover. Used for the panel
/// footer and other low-emphasis actions.
struct GhostButtonStyle: ButtonStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration, theme: theme)
    }

    private struct HoverLabel: View {
        let configuration: ButtonStyleConfiguration
        let theme: Theme
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.inkSoft)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(hovering ? theme.inset : .clear, in: RoundedRectangle(cornerRadius: 7))
                .opacity(configuration.isPressed ? 0.55 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
