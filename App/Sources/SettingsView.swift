// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import KEFKit
import SwiftUI

/// The Settings scene (SPEC §9): manage configured speakers, add discovered ones,
/// and app preferences (launch-at-login, show-in-Dock, CLI step).
struct SettingsView: View {
    @ObservedObject var store: SpeakerStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            speakersTab.tabItem { Label("Speakers", systemImage: "hifispeaker.2") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 420)
        .padding()
    }

    // MARK: - Speakers

    private var speakersTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configured").font(.headline)
            if store.speakers.isEmpty {
                Text("None yet — scan below and click Add.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.speakers) { vm in
                    ConfiguredRow(
                        vm: vm,
                        isDefault: store.defaultSpeakerId == vm.id,
                        onRename: { store.rename(id: vm.id, to: $0) },
                        onSetHost: { store.setHost(id: vm.id, host: $0) },
                        onMakeDefault: { store.setDefault(id: vm.id) },
                        onRemove: { store.remove(id: vm.id) })
                }
            }

            Divider().padding(.vertical, 4)

            HStack {
                Text("Discovered").font(.headline)
                Spacer()
                Button(store.isScanning ? "Scanning…" : "Rescan") { store.rescan() }
                    .disabled(store.isScanning)
            }
            if store.discovered.isEmpty {
                Text("Click Rescan to find KEF speakers on your network.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.discovered, id: \.mac) { d in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(d.name.isEmpty ? d.model : d.name)
                            Text("\(d.host) · \(d.model)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let added = store.speakers.contains { $0.id.caseInsensitiveCompare(d.mac) == .orderedSame }
                        Button(added ? "Added" : "Add") { store.add(d) }.disabled(added)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            Toggle("Show in Dock", isOn: Binding(
                get: { settings.showInDock }, set: { settings.setShowInDock($0) }))
            Divider()
            Stepper("CLI default step: \(store.cliStep)", value: Binding(
                get: { store.cliStep }, set: { store.setCliStep($0) }), in: 1...10)
            Text("Used by `kefbar up` / `kefbar down` when no step is given.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// One configured speaker with in-place rename / IP edit / default / remove.
private struct ConfiguredRow: View {
    let vm: SpeakerVM
    let isDefault: Bool
    let onRename: (String) -> Void
    let onSetHost: (String) -> Void
    let onMakeDefault: () -> Void
    let onRemove: () -> Void

    @State private var name: String
    @State private var host: String

    init(vm: SpeakerVM, isDefault: Bool,
         onRename: @escaping (String) -> Void, onSetHost: @escaping (String) -> Void,
         onMakeDefault: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.vm = vm
        self.isDefault = isDefault
        self.onRename = onRename
        self.onSetHost = onSetHost
        self.onMakeDefault = onMakeDefault
        self.onRemove = onRemove
        _name = State(initialValue: vm.name)
        _host = State(initialValue: vm.host)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $name).frame(width: 140).onSubmit { onRename(name) }
            TextField("IP address", text: $host).frame(width: 120).onSubmit { onSetHost(host) }
            if isDefault {
                Text("default").font(.caption).foregroundStyle(.blue)
            } else {
                Button("Make default") { onMakeDefault() }.font(.caption)
            }
            Spacer()
            Button(role: .destructive) { onRemove() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}
