// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation
import ServiceManagement
import SwiftUI

/// App-level preferences (SPEC §9). Launch-at-login via `SMAppService` (no sudo,
/// no helper). Plus the UI preferences (Oatmeal palette and appearance mode),
/// persisted in `UserDefaults` (the CLI doesn't care about theming, so these
/// stay app-only rather than in the shared config).
@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin = false

    @Published var palette: Palette {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: Keys.palette) }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    private enum Keys {
        static let palette = "palette"
        static let appearance = "appearance"
    }

    init() {
        let defaults = UserDefaults.standard
        palette = Palette(rawValue: defaults.string(forKey: Keys.palette) ?? "") ?? .olive
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        // Agent app: LSUIElement in Info.plist keeps us out of the Dock, with no
        // activation-policy juggling now that "Show in Dock" is gone.
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
}
