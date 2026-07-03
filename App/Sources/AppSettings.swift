// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import AppKit
import ServiceManagement
import SwiftUI

/// App-level preferences (SPEC §9): launch-at-login via `SMAppService` and Dock
/// presence via the activation policy. No sudo, no helper — the modern APIs.
@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin = false
    @Published private(set) var showInDock = false

    init() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        applyDockPolicy()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            AppLog.log("launch-at-login toggle failed: \(error)")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func setShowInDock(_ enabled: Bool) {
        showInDock = enabled
        UserDefaults.standard.set(enabled, forKey: "showInDock")
        applyDockPolicy()
    }

    /// Agent (`.accessory`) by default; `.regular` shows a Dock icon. LSUIElement in
    /// Info.plist keeps us out of the Dock at launch until this flips it.
    private func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
