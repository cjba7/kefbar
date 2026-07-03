// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import AppKit
import SwiftUI

/// Hosts the Settings UI in a plain, resizable `NSWindow`, opened from the menu.
///
/// SwiftUI's `Settings` scene ships fixed-size and continually re-clamps the
/// window's max size, so forcing it resizable is racy. Managing our own window
/// sidesteps all of that: a standard titled window is natively resizable, opens
/// only when asked (never at launch), and reuses one instance.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(store: SpeakerStore, settings: AppSettings) {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // The floor lives on the SwiftUI content so the hosting view carries it
        // (window.minSize alone isn't honoured with an NSHostingView content view).
        let root = SettingsView(store: store, settings: settings)
            .preferredColorScheme(settings.appearance.colorScheme)
            .frame(minWidth: 380, minHeight: 280)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "kefbar Settings"
        window.contentView = NSHostingView(rootView: root)
        window.minSize = NSSize(width: 380, height: 280)
        window.isReleasedWhenClosed = false   // keep it for reuse when closed
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
