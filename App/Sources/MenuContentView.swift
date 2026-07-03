// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import AppKit
import SwiftUI

/// The MenuBarExtra panel: a calm, editorial control surface. One row per
/// configured speaker: the volume value set as the hero in a serif face,
/// paired with a quiet fader, plus a slim footer. Rescan lives in Settings now.
struct MenuContentView: View {
    @ObservedObject var store: SpeakerStore
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var envScheme

    private var theme: Theme {
        Theme(palette: settings.palette, scheme: settings.appearance.colorScheme ?? envScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.speakers.isEmpty {
                emptyState
            } else {
                ForEach(Array(store.speakers.enumerated()), id: \.element.id) { index, vm in
                    SpeakerRowView(vm: vm, theme: theme)
                    if index < store.speakers.count - 1 {
                        Rectangle().fill(theme.line).frame(height: 1).padding(.horizontal, 12)
                    }
                }
            }
            footer
        }
        .frame(width: 300)
        .background(theme.panel)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No speakers yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text("Open Settings to find your KEF speakers on the network.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.line).frame(height: 1)
            HStack(spacing: 2) {
                settingsButton
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(GhostButtonStyle(theme: theme))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // Opens our own resizable settings window (SettingsWindowController).
    private var settingsButton: some View {
        Button("Settings…") {
            SettingsWindowController.shared.show(store: store, settings: settings)
        }
        .buttonStyle(GhostButtonStyle(theme: theme))
    }
}

/// A single speaker: name + Uni-Q power mark + model/state, the serif volume
/// readout, the fader, and a mute button. Standby speakers dim.
struct SpeakerRowView: View {
    @ObservedObject var vm: SpeakerVM
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                UniQMark(color: markColor)
                Text(vm.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Text(metaText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(vm.reachable ? theme.inkFaint : theme.warn)
            }

            HStack(alignment: .center, spacing: 13) {
                readout
                VolumeFader(
                    value: vm.volume,
                    range: 0...Double(max(vm.maxVolume, 1)),
                    theme: theme,
                    onChange: { vm.onSlider($0) })
                muteButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .opacity(vm.isStandby ? 0.55 : 1)
    }

    private var markColor: Color {
        if !vm.reachable { return theme.warn }
        if vm.isOn { return theme.on }
        return theme.inkFaint
    }

    private var metaText: String {
        if !vm.reachable { return "unreachable" }
        let power = vm.isOn ? "on" : (vm.isStandby ? "standby" : "")
        return [vm.model, power].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(vm.volume.rounded()))")
                    .font(.system(size: 37, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(vm.muted ? theme.inkFaint : theme.ink)
                Text("/\(vm.maxVolume)")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(theme.inkFaint)
            }
            Text(vm.muted ? "MUTED" : "VOLUME")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(theme.inkFaint)
        }
        .frame(minWidth: 58, alignment: .leading)
    }

    private var muteButton: some View {
        Button { vm.toggleMute() } label: {
            Image(systemName: vm.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(vm.muted ? theme.warn : theme.inkSoft)
                .frame(width: 34, height: 34)
                .background(theme.inset, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(vm.muted ? "Unmute" : "Mute")
    }
}
