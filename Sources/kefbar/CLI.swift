// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation
import KEFKit

/// The resolved target of a command: where to connect and how to clamp.
struct Target {
    let host: String
    let maxVolume: Int
    let id: String        // key for mute-state (MAC for configured, host for ad-hoc)
    let name: String?
}

enum CLI {
    // MARK: - Entry

    static func main(_ args: [String]) async -> Int32 {
        let parsed: ParsedArgs
        do {
            parsed = try ArgParser.parse(args)
        } catch let CLIError.usage(m) {
            errln("kefbar: \(m)")
            return 2
        } catch {
            errln("kefbar: \(error.localizedDescription)")
            return 2
        }

        if parsed.version {
            print(versionText)
            return 0
        }
        if parsed.help {
            print(usageText)
            return 0
        }
        guard parsed.command != nil else {
            errln(usageText)
            return 2
        }

        do {
            try await run(parsed)
            return 0
        } catch let CLIError.usage(m) {
            errln("kefbar: \(m)")
            return 2
        } catch let CLIError.unreachable(m) {
            errln("kefbar: \(m)")
            return 3
        } catch let CLIError.firmware(m) {
            errln("kefbar: \(m)")
            return 4
        } catch let e as KEFError {
            switch e {
            case .writeUnsupported(let m):
                errln("kefbar: \(m)")
                return 4
            case .unreachable(let m), .badResponse(let m):
                errln("kefbar: \(m)")
                return 3
            }
        } catch {
            errln("kefbar: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - Dispatch

    static func run(_ p: ParsedArgs) async throws {
        switch p.command! {
        case "get": try await cmdGet(p)
        case "set": try await cmdSet(p)
        case "up": try await cmdUpDown(p, sign: +1)
        case "down": try await cmdUpDown(p, sign: -1)
        case "mute": try await cmdMute(p)
        case "unmute": try await cmdUnmute(p)
        case "status": try await cmdStatus(p)
        case "list": try cmdList(p)
        case "discover": try await cmdDiscover(p)
        default:
            throw CLIError.usage("unknown command '\(p.command!)'")
        }
    }

    // MARK: - Resolution

    /// Load config, mapping read errors to a usage error (exit 2).
    static func loadConfig() throws -> Config {
        do { return try Config.load() }
        catch { throw CLIError.usage("cannot read config: \(error.localizedDescription)") }
    }

    /// Resolve which speaker to talk to (SPEC §11). When `needMaxVolume` and the
    /// target is an ad-hoc `--host`, fetch its maxVolume live so clamping is right.
    static func resolveTarget(_ p: ParsedArgs, needMaxVolume: Bool) async throws -> Target {
        var config = Config()
        if p.host == nil {
            config = try loadConfig()
        }
        switch Config.resolve(config: config, host: p.host, speakerName: p.speaker) {
        case .success(.adHocHost(let h)):
            var maxV = 100
            if needMaxVolume {
                maxV = (try? await KEFClient(host: h).maxVolume()) ?? 100
            }
            return Target(host: h, maxVolume: maxV, id: h, name: nil)
        case .success(.configured(let s)):
            return Target(host: s.host, maxVolume: s.maxVolume, id: s.id, name: s.name)
        case .failure(.notFound(let name)):
            throw CLIError.usage("no speaker named '\(name)' in config")
        case .failure(.noneConfigured):
            throw CLIError.usage("no speakers configured; pass --host <ip> or add one via the app")
        case .failure(.ambiguous(let names)):
            let list = names.map { "  \($0)" }.joined(separator: "\n")
            throw CLIError.usage(
                "multiple speakers configured; pass --speaker <name> or --host <ip>\n\(list)")
        }
    }

    // MARK: - Commands

    static func cmdGet(_ p: ParsedArgs) async throws {
        let t = try await resolveTarget(p, needMaxVolume: false)
        let v = try await KEFClient(host: t.host).volume()
        emitVolume(v, json: p.json)
    }

    static func cmdSet(_ p: ParsedArgs) async throws {
        guard let arg = p.positionals.first, let value = Int(arg) else {
            throw CLIError.usage("set requires a volume 0-100")
        }
        let t = try await resolveTarget(p, needMaxVolume: true)
        let target = Config.clampVolume(value, maxVolume: t.maxVolume)
        let r = try await KEFClient(host: t.host).setVolume(target)  // absolute: no flock (SPEC §10)
        warnIfLegacy(r)
        emitVolume(r.volume, json: p.json)
    }

    static func cmdUpDown(_ p: ParsedArgs, sign: Int) async throws {
        let step = try resolveStep(p)
        guard Config.isValidStep(step) else { throw CLIError.usage("step must be 1-10") }

        let t = try await resolveTarget(p, needMaxVolume: true)

        // Serialise the read-modify-write so rapid taps sum correctly (SPEC §10).
        let lock = try FileLock(url: try AppSupport.lockURL)
        lock.lock()
        defer { lock.unlock() }

        let client = KEFClient(host: t.host)
        let current = try await client.volume()
        let target = Config.clampVolume(current + sign * step, maxVolume: t.maxVolume)
        let r = try await client.setVolume(target)
        warnIfLegacy(r)
        emitVolume(r.volume, json: p.json)
    }

    /// Step precedence: positional arg, then --step, then configured cliStep.
    static func resolveStep(_ p: ParsedArgs) throws -> Int {
        if let arg = p.positionals.first {
            guard let n = Int(arg) else { throw CLIError.usage("step must be 1-10") }
            return n
        }
        if let n = p.step { return n }
        return try loadConfig().cliStep
    }

    static func cmdMute(_ p: ParsedArgs) async throws {
        let t = try await resolveTarget(p, needMaxVolume: false)
        let store = try FileMuteStore()
        let r = try await KEFClient(host: t.host).mute(id: t.id, store: store)
        warnIfLegacy(r)
        emitVolume(r.volume, json: p.json)
    }

    static func cmdUnmute(_ p: ParsedArgs) async throws {
        let t = try await resolveTarget(p, needMaxVolume: true)
        let store = try FileMuteStore()
        let fallback = Config.clampVolume(15, maxVolume: t.maxVolume)
        let r = try await KEFClient(host: t.host)
            .unmute(id: t.id, store: store, fallback: fallback, maxVolume: t.maxVolume)
        warnIfLegacy(r)
        emitVolume(r.volume, json: p.json)
    }

    static func cmdStatus(_ p: ParsedArgs) async throws {
        let t = try await resolveTarget(p, needMaxVolume: false)
        let client = KEFClient(host: t.host)
        async let mf = client.modelFirmware()
        async let nm = client.deviceName()
        async let pw = client.status()
        async let vl = client.volume()
        let (model, firmware) = try await mf
        let name = try await nm
        let power = try await pw
        let volume = try await vl

        if p.json {
            emitJSON([
                "name": name, "model": model, "power": power,
                "volume": volume, "firmware": firmware,
            ])
        } else {
            print("Name:     \(name)")
            print("Model:    \(model)")
            print("Power:    \(power)")
            print("Volume:   \(volume)")
            print("Firmware: \(firmware)")
        }
    }

    static func cmdList(_ p: ParsedArgs) throws {
        let config = try loadConfig()
        if p.json {
            let arr: [[String: Any]] = config.speakers.map { s in
                [
                    "id": s.id, "name": s.name, "host": s.host,
                    "model": s.model ?? "", "maxVolume": s.maxVolume,
                    "firmware": s.firmware ?? "",
                    "default": s.id == config.defaultSpeakerId,
                ]
            }
            emitJSON(arr)
        } else {
            if config.speakers.isEmpty {
                print("(no speakers configured)")
                return
            }
            for s in config.speakers {
                let mark = s.id == config.defaultSpeakerId ? " *" : ""
                print("\(s.name) -> \(s.host)\(mark)")
            }
        }
    }

    static func cmdDiscover(_ p: ParsedArgs) async throws {
        let found = await Discovery.discover()
        if p.json {
            emitJSON(found.map { s in
                [
                    "mac": s.mac, "host": s.host, "name": s.name,
                    "model": s.model, "firmware": s.firmware, "maxVolume": s.maxVolume,
                ]
            })
        } else if found.isEmpty {
            print("no KEF speakers found on the LAN")
        } else {
            for s in found {
                print("\(s.name)  \(s.host)  [\(s.model), fw \(s.firmware), MAC \(s.mac)]")
            }
        }
    }

    // MARK: - Output helpers

    static func emitVolume(_ v: Int, json: Bool) {
        if json { emitJSON(["volume": v]) } else { print(v) }
    }

    static func emitJSON(_ obj: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    static func warnIfLegacy(_ r: WriteResult) {
        if r.usedLegacyGET {
            errln("kefbar: warning: speaker used legacy GET-only write (old firmware); update recommended")
        }
    }
}

/// Write a line to stderr.
func errln(_ s: String) {
    try? FileHandle.standardError.write(contentsOf: Data((s + "\n").utf8))
}
