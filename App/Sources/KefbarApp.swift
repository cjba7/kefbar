// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import SwiftUI

/// kefbar menu-bar app (SPEC §9). Agent by default (LSUIElement in Info.plist);
/// a `MenuBarExtra` window scene plus a resizable `Settings` scene, sharing one
/// `SpeakerStore` and `AppSettings`. Both scenes honour the chosen appearance.
@main
struct KefbarApp: App {
    @StateObject private var store = SpeakerStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra("kefbar", systemImage: "speaker.wave.2") {
            MenuContentView(store: store, settings: settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .menuBarExtraStyle(.window)
        // Settings is a plain, resizable NSWindow managed by
        // SettingsWindowController (opened from the menu) rather than a SwiftUI
        // Settings scene, which ships fixed-size and resists being made resizable.
    }
}
