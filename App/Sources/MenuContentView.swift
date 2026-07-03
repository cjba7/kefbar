// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import AppKit
import SwiftUI

/// The MenuBarExtra popover: one row per configured speaker, plus a footer.
struct MenuContentView: View {
    @ObservedObject var store: SpeakerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.speakers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No speakers configured").font(.headline)
                    Text("Open Settings to discover and add your KEF speakers.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.speakers) { vm in
                    SpeakerRowView(vm: vm)
                }
            }

            Divider()

            HStack(spacing: 12) {
                settingsButton
                Button(store.isScanning ? "Scanning…" : "Rescan") { store.rescan() }
                    .disabled(store.isScanning)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink { Text("Settings…") }
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

/// A single speaker: name + power dot + value, mute button, and the volume slider.
struct SpeakerRowView: View {
    @ObservedObject var vm: SpeakerVM

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.isOn ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(vm.name).font(.headline)
                Spacer()
                Text("\(Int(vm.volume.rounded()))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button { vm.toggleMute() } label: {
                    Image(systemName: vm.muted ? "speaker.slash.fill" : "speaker.fill")
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)

                Slider(
                    value: Binding(get: { vm.volume }, set: { vm.onSlider($0) }),
                    in: 0...Double(max(vm.maxVolume, 1)))
            }

            if !vm.reachable {
                Text("unreachable").font(.caption2).foregroundStyle(.orange)
            }
        }
        .opacity(vm.isStandby ? 0.5 : 1)  // dim standby speakers
    }
}
