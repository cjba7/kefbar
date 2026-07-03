// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// The one privileged operation (SPEC §12): symlink the CLI bundled at
/// `kefbar.app/Contents/Helpers/kefbar` into `/usr/local/bin`. Uses `osascript`
/// `with administrator privileges`, so macOS shows its native password prompt —
/// the app never handles the password. If declined, the CLI still runs via its
/// full bundle path.
enum CLIInstaller {
    static let linkPath = "/usr/local/bin/kefbar"

    /// Absolute path to the CLI inside this app bundle, if present & executable.
    static var bundledCLI: String? {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/kefbar")
        return FileManager.default.isExecutableFile(atPath: helper.path) ? helper.path : nil
    }

    /// True when `/usr/local/bin/kefbar` is a symlink into a kefbar.app bundle.
    static var isInstalled: Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
        else { return false }
        if let cli = bundledCLI, dest == cli { return true }
        return dest.contains("kefbar.app/Contents/Helpers/kefbar")
    }

    enum InstallError: LocalizedError {
        case cliMissing
        case scriptFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .cliMissing: return "The bundled command-line tool wasn't found in the app."
            case .scriptFailed(let code): return "The install helper exited with code \(code)."
            }
        }
    }

    static func install() throws {
        guard let cli = bundledCLI else { throw InstallError.cliMissing }
        try runPrivileged(
            "mkdir -p /usr/local/bin && ln -sf \\\"\(cli)\\\" \\\"\(linkPath)\\\"")
    }

    static func uninstall() throws {
        try runPrivileged("rm -f \\\"\(linkPath)\\\"")
    }

    /// Run a shell command under `do shell script … with administrator
    /// privileges`. The inner `\"` escapes survive into AppleScript so paths with
    /// spaces are quoted for the shell.
    private static func runPrivileged(_ shellCommand: String) throws {
        let source = "do shell script \"\(shellCommand)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        try proc.run()
        proc.waitUntilExit()
        // osascript returns -128 when the user cancels the auth prompt; treat any
        // non-zero as "not done" and let the caller re-read isInstalled.
        if proc.terminationStatus != 0 {
            throw InstallError.scriptFailed(proc.terminationStatus)
        }
    }
}
