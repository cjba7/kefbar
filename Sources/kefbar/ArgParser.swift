// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// CLI-level errors, mapped to exit codes in `CLI.main` (SPEC §11):
/// usage -> 2, unreachable -> 3, firmware (write unsupported) -> 4.
enum CLIError: Error {
    case usage(String)
    case unreachable(String)
    case firmware(String)
}

/// Parsed command line: a subcommand, its positionals, and global flags.
struct ParsedArgs {
    var command: String?
    var positionals: [String] = []
    var speaker: String?
    var host: String?
    var step: Int?
    var json = false
    var help = false
    var version = false
}

enum ArgParser {
    /// Hand-rolled parsing — no third-party deps (SPEC §3).
    static func parse(_ args: [String]) throws -> ParsedArgs {
        var p = ParsedArgs()
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--help", "-h":
                p.help = true
            case "--version", "-V":
                p.version = true
            case "--json":
                p.json = true
            case "--speaker", "-s":
                i += 1
                guard i < args.count else { throw CLIError.usage("--speaker requires a value") }
                p.speaker = args[i]
            case "--host", "-H":
                i += 1
                guard i < args.count else { throw CLIError.usage("--host requires a value") }
                p.host = args[i]
            case "--step":
                i += 1
                guard i < args.count else { throw CLIError.usage("--step requires a value") }
                guard let n = Int(args[i]) else { throw CLIError.usage("step must be 1-10") }
                p.step = n
            default:
                if a.hasPrefix("--") {
                    throw CLIError.usage("unknown flag '\(a)'")
                }
                if p.command == nil {
                    p.command = a
                } else {
                    p.positionals.append(a)
                }
            }
            i += 1
        }
        return p
    }
}

let usageText = """
kefbar — control KEF W2 speaker volume from the command line

USAGE:
  kefbar <command> [args] [flags]

COMMANDS:
  get                 print current volume (0-100)
  set <0-100>         set absolute volume (clamped to maxVolume)
  up   [step]         raise volume (step default = configured cliStep, max 10)
  down [step]         lower volume (step default = configured cliStep, max 10)
  mute                mute (volume 0, remembers prior level)
  unmute              restore volume to the pre-mute level
  status              print model, name, power, volume, firmware
  list                list configured speakers (default marked with *)
  discover            scan the LAN for KEF speakers (does not modify config)

FLAGS:
  -s, --speaker <name>   target a configured speaker by name
  -H, --host <ip>        target a speaker directly by IP/host
      --step <n>         step for up/down (1-10)
      --json             machine-readable output
  -h, --help             show this help
  -V, --version          show version

EXIT CODES:
  0 success   2 usage/resolution   3 unreachable   4 firmware too old (write unsupported)
"""

let versionText = "kefbar 0.1.0 (M1)"
