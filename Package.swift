// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import PackageDescription

let package = Package(
    name: "kefbar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "KEFKit", targets: ["KEFKit"]),
        .executable(name: "kefbar", targets: ["kefbar"]),
        .executable(name: "KefbarApp", targets: ["KefbarApp"]),
    ],
    targets: [
        // Shared library: KEF HTTP client, config, discovery contract (M0).
        .target(
            name: "KEFKit"
        ),
        // CLI executable (M1). Talks directly to the speaker; no daemon.
        .executableTarget(
            name: "kefbar",
            dependencies: ["KEFKit"],
            // Info.plist is embedded via the linker flag below, not bundled as a
            // resource — exclude it so SwiftPM doesn't flag it as unhandled.
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed an Info.plist (carrying NSLocalNetworkUsageDescription) into
                // the CLI Mach-O. On macOS 15+ a standalone binary with no usage
                // description can never be prompted for Local Network access, so LAN
                // requests are silently denied; the embedded plist lets macOS show
                // the prompt and record a grant. Path is relative to the package root.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/kefbar/Info.plist",
                ])
            ]
        ),
        // Menu-bar app (M3): SwiftUI MenuBarExtra + Settings. Built into an .app
        // bundle by `make app` (a bare SwiftPM executable can't be a menu-bar agent).
        .executableTarget(
            name: "KefbarApp",
            dependencies: ["KEFKit"],
            path: "App/Sources"
        ),
        .testTarget(
            name: "KEFKitTests",
            dependencies: ["KEFKit"]
        ),
    ]
)
