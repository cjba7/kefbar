// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import KEFKit
import SwiftUI

/// The Settings scene (SPEC §9), reorganised into four clearly separated tabs:
/// Speakers · General · CLI · UI. A custom underlined tab bar (matching the
/// design concept, not the stock TabView chrome) sits above themed content. The
/// window is made resizable with a minimum size via its NSWindow.
struct SettingsView: View {
    @ObservedObject var store: SpeakerStore
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var envScheme
    @State private var tab: SettingsTab = .speakers

    private var theme: Theme {
        Theme(palette: settings.palette, scheme: settings.appearance.colorScheme ?? envScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $tab, theme: theme)
            Rectangle().fill(theme.line).frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.ground)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .speakers: SpeakersTab(store: store, theme: theme)
        case .general: GeneralTab(settings: settings, theme: theme)
        case .cli: CLITab(store: store, theme: theme)
        case .ui: UITab(settings: settings, theme: theme)
        }
    }
}

// MARK: - Custom tab bar

enum SettingsTab: String, CaseIterable, Identifiable {
    case speakers, general, cli, ui
    var id: String { rawValue }
    var label: String {
        switch self {
        case .speakers: return "Speakers"
        case .general: return "General"
        case .cli: return "CLI"
        case .ui: return "UI"
        }
    }
    var symbol: String {
        switch self {
        case .speakers: return "hifispeaker.2"
        case .general: return "gearshape"
        case .cli: return "terminal"
        case .ui: return "paintpalette"
        }
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab
    let theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { t in
                let selected = t == selection
                Button { selection = t } label: {
                    HStack(spacing: 7) {
                        Image(systemName: t.symbol).font(.system(size: 13))
                        Text(t.label).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(selected ? theme.ink : theme.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selected ? theme.accent : Color.clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .background(theme.panel)
    }
}

// MARK: - Tabs

private struct SpeakersTab: View {
    @ObservedObject var store: SpeakerStore
    let theme: Theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Configured", theme: theme)
                if store.speakers.isEmpty {
                    Caption(text: "None yet — scan below and add your speakers.", theme: theme)
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.speakers) { vm in
                            ConfiguredRow(
                                vm: vm, isDefault: store.defaultSpeakerId == vm.id, theme: theme,
                                onRename: { store.rename(id: vm.id, to: $0) },
                                onSetHost: { store.setHost(id: vm.id, host: $0) },
                                onMakeDefault: { store.setDefault(id: vm.id) },
                                onRemove: { store.remove(id: vm.id) })
                        }
                    }
                }

                Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 2)

                HStack {
                    SectionLabel(text: "Discovered", theme: theme)
                    Spacer()
                    Button(store.isScanning ? "Scanning…" : "Rescan") { store.rescan() }
                        .buttonStyle(QuietButtonStyle(theme: theme, small: true))
                        .disabled(store.isScanning)
                }
                if store.discovered.isEmpty {
                    Caption(text: "Click Rescan to find KEF speakers on your network.", theme: theme)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.discovered, id: \.mac) { d in
                            DiscoveredRow(
                                d: d,
                                added: store.speakers.contains { $0.id.caseInsensitiveCompare(d.mac) == .orderedSame },
                                theme: theme,
                                onAdd: { store.add(d) })
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let theme: Theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Startup", theme: theme)
                SettingRow(
                    title: "Launch at login",
                    subtitle: "Start kefbar automatically when you sign in.",
                    theme: theme
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(theme.accent)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CLITab: View {
    @ObservedObject var store: SpeakerStore
    let theme: Theme
    @State private var installed = CLIInstaller.isInstalled
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Command-line tool", theme: theme)

                SettingRow(
                    title: installed ? "kefbar is installed" : "Install kefbar in your PATH",
                    subtitle: "Links the bundled tool to /usr/local/bin. Asks for your password once.",
                    theme: theme
                ) {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small) }
                        if installed {
                            Button("Uninstall") { run { try CLIInstaller.uninstall() } }
                                .buttonStyle(QuietButtonStyle(theme: theme))
                        } else {
                            Button("Install CLI") { run { try CLIInstaller.install() } }
                                .buttonStyle(PrimaryButtonStyle(theme: theme))
                                .disabled(CLIInstaller.bundledCLI == nil)
                        }
                    }
                    .disabled(busy)
                }

                if CLIInstaller.bundledCLI == nil {
                    Caption(text: "Run from the built kefbar.app to install — the CLI ships inside the bundle.", theme: theme)
                }
                if let note { Caption(text: note, theme: theme) }

                Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 2)

                SettingRow(
                    title: "Default step",
                    subtitle: "Used by kefbar up / down when no step is given.",
                    theme: theme
                ) {
                    ThemedStepper(value: store.cliStep, range: 1...10, theme: theme) { store.setCliStep($0) }
                }

                Text("Wire hardware keys to `kefbar up 3` / `kefbar down 3` from Logi Options+, BetterTouchTool, or Keyboard Maestro.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inset, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Run a privileged op off the main thread (the auth prompt blocks), then
    /// re-read install state. A throw (including a cancelled prompt) just leaves
    /// state unchanged with a gentle note.
    private func run(_ op: @escaping () throws -> Void) {
        busy = true
        note = nil
        Task.detached {
            let failed: Bool
            do { try op(); failed = false } catch { failed = true }
            await MainActor.run {
                busy = false
                installed = CLIInstaller.isInstalled
                note = failed ? "That didn't finish — you can try again." : nil
            }
        }
    }
}

private struct UITab: View {
    @ObservedObject var settings: AppSettings
    let theme: Theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Palette", theme: theme)
                PaletteChooser(selection: $settings.palette, theme: theme)

                Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 4)

                SectionLabel(text: "Appearance", theme: theme)
                AppearanceChooser(selection: $settings.appearance, theme: theme).frame(maxWidth: 360)
                Caption(text: "Match macOS follows your system — slipping into dark in the evening.", theme: theme)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Rows

/// One configured speaker: in-place rename / IP edit / default / remove.
private struct ConfiguredRow: View {
    let vm: SpeakerVM
    let isDefault: Bool
    let theme: Theme
    let onRename: (String) -> Void
    let onSetHost: (String) -> Void
    let onMakeDefault: () -> Void
    let onRemove: () -> Void

    @State private var name: String
    @State private var host: String

    init(vm: SpeakerVM, isDefault: Bool, theme: Theme,
         onRename: @escaping (String) -> Void, onSetHost: @escaping (String) -> Void,
         onMakeDefault: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.vm = vm
        self.isDefault = isDefault
        self.theme = theme
        self.onRename = onRename
        self.onSetHost = onSetHost
        self.onMakeDefault = onMakeDefault
        self.onRemove = onRemove
        _name = State(initialValue: vm.name)
        _host = State(initialValue: vm.host)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .tint(theme.accent2)
                    .onSubmit { onRename(name) }
                HStack(spacing: 6) {
                    TextField("IP address", text: $host)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(theme.inkSoft)
                        .tint(theme.accent2)
                        .frame(maxWidth: 120)
                        .onSubmit { onSetHost(host) }
                    if !vm.model.isEmpty {
                        Text("· \(vm.model)").font(.system(size: 11)).foregroundStyle(theme.inkFaint)
                    }
                }
            }
            Spacer(minLength: 8)
            if isDefault {
                Text("Default")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                    .foregroundStyle(theme.accentInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.accent, in: Capsule())
            } else {
                Button("Make default") { onMakeDefault() }
                    .buttonStyle(QuietButtonStyle(theme: theme, small: true))
            }
            Button { onRemove() } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(theme.inkFaint)
            }
            .buttonStyle(.plain)
            .help("Remove speaker")
        }
        .padding(12)
        .background(theme.inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.line, lineWidth: 1))
    }
}

private struct DiscoveredRow: View {
    let d: DiscoveredSpeaker
    let added: Bool
    let theme: Theme
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name.isEmpty ? d.model : d.name)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.ink)
                Text("\(d.host) · \(d.model)")
                    .font(.system(size: 11)).foregroundStyle(theme.inkFaint)
            }
            Spacer()
            if added {
                Text("Added").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.inkFaint)
            } else {
                Button("Add") { onAdd() }.buttonStyle(PrimaryButtonStyle(theme: theme))
            }
        }
        .padding(11)
        .background(theme.inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.line, lineWidth: 1))
    }
}

// MARK: - Themed controls

private struct SectionLabel: View {
    let text: String
    let theme: Theme
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(1.3)
            .foregroundStyle(theme.inkFaint)
    }
}

private struct Caption: View {
    let text: String
    let theme: Theme
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(theme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let theme: Theme
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(theme.ink)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 6)
    }
}

private struct ThemedStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let theme: Theme
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) { onChange(value - 1) }
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.ink)
                .frame(minWidth: 42, minHeight: 28)
                .background(theme.panel)
                .overlay(Rectangle().fill(theme.line).frame(width: 1), alignment: .leading)
                .overlay(Rectangle().fill(theme.line).frame(width: 1), alignment: .trailing)
            button("plus", enabled: value < range.upperBound) { onChange(value + 1) }
        }
        .background(theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.lineStrong, lineWidth: 1))
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? theme.ink : theme.inkFaint)
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

private struct PaletteChooser: View {
    @Binding var selection: Palette
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Palette.allCases) { p in
                let selected = p == selection
                Button { selection = p } label: {
                    HStack(spacing: 8) {
                        Circle().fill(swatch(p)).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                        Text(p.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(selected ? theme.ink : theme.inkSoft)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(selected ? theme.inset : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(selected ? theme.accent : theme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func swatch(_ p: Palette) -> Color {
        let s = p.ramp[5]
        return Color(oklchL: s.l, c: s.c, h: s.h)
    }
}

private struct AppearanceChooser: View {
    @Binding var selection: AppearanceMode
    let theme: Theme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppearanceMode.allCases) { m in
                let selected = m == selection
                Button { selection = m } label: {
                    Text(m.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? theme.ink : theme.inkSoft)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(selected ? theme.panel : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.inset, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line, lineWidth: 1))
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    let theme: Theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.accentInk)
            .padding(.horizontal, 15).padding(.vertical, 8)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    let theme: Theme
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .medium))
            .foregroundStyle(theme.inkSoft)
            .padding(.horizontal, small ? 11 : 14).padding(.vertical, small ? 6 : 8)
            .background(theme.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
