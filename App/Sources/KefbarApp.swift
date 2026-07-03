// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import SwiftUI

/// kefbar menu-bar app (SPEC §9). Agent by default (LSUIElement in Info.plist);
/// a `MenuBarExtra` window scene plus a `Settings` scene, sharing one `SpeakerStore`.
@main
struct KefbarApp: App {
    @StateObject private var store = SpeakerStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra("kefbar", systemImage: "speaker.wave.2") {
            MenuContentView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, settings: settings)
        }
    }
}
