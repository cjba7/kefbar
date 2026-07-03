// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation
import Network

/// Bonjour browse over the confirmed `_airplay._tcp` type (SPEC §6/§16.7 — KEF W2
/// speakers advertise there with `manufacturer=KEF`; `_kef._tcp` does not exist).
/// This is the fast primary path: it resolves matching instances to IPs, which the
/// caller then contract-probes to confirm each is really a KEF W2.
///
/// Requires the browsed types to be declared in `NSBonjourServices` (embedded
/// Info.plist for the CLI; app Info.plist for the GUI) on macOS 15+.
enum BonjourBrowser {

    private struct Candidate {
        let endpoint: NWEndpoint
        let manufacturer: String?
    }

    /// Resume a continuation at most once, from whichever handler fires first.
    private final class OneShot<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let cont: CheckedContinuation<T, Never>
        init(_ cont: CheckedContinuation<T, Never>) { self.cont = cont }
        func resume(_ value: T) {
            lock.lock(); defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            cont.resume(returning: value)
        }
    }

    /// Lock-guarded mutable cell for state shared across handlers.
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ value: T) { self.value = value }
        func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ value: T) { lock.lock(); self.value = value; lock.unlock() }
    }

    /// Browse `_airplay._tcp`, drop devices that advertise a non-KEF manufacturer
    /// (e.g. HomePods), and resolve the rest to IPv4 addresses.
    static func browseKEFAddresses(timeout: TimeInterval) async -> [String] {
        let candidates = await browse(type: "_airplay._tcp", domain: "local.", timeout: timeout)
        var ips: Set<String> = []
        await withTaskGroup(of: String?.self) { group in
            for candidate in candidates {
                if let mfr = candidate.manufacturer,
                   mfr.range(of: "KEF", options: .caseInsensitive) == nil {
                    continue  // definitely not a KEF — skip the resolve/probe
                }
                group.addTask { await resolveIPv4(candidate.endpoint, timeout: 1.5) }
            }
            for await ip in group {
                if let ip { ips.insert(ip) }
            }
        }
        return Array(ips)
    }

    /// Collect the set of instances seen for `type` over `timeout` seconds.
    private static func browse(type: String, domain: String, timeout: TimeInterval) async
        -> [Candidate]
    {
        await withCheckedContinuation { (cont: CheckedContinuation<[Candidate], Never>) in
            let once = OneShot(cont)
            let box = Box<[Candidate]>([])
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjour(type: type, domain: domain), using: params)

            browser.browseResultsChangedHandler = { results, _ in
                box.set(results.map { result in
                    var manufacturer: String?
                    if case let .bonjour(txt) = result.metadata {
                        manufacturer = txt["manufacturer"]
                    }
                    return Candidate(endpoint: result.endpoint, manufacturer: manufacturer)
                })
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    browser.cancel()
                    once.resume(box.get())
                }
            }
            browser.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                browser.cancel()
                once.resume(box.get())
            }
        }
    }

    /// Resolve a Bonjour endpoint to an IPv4 string by briefly opening a connection
    /// and reading the resolved path's remote address.
    private static func resolveIPv4(_ endpoint: NWEndpoint, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let once = OneShot(cont)
            let conn = NWConnection(to: endpoint, using: .tcp)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var ip: String?
                    if case let .hostPort(host, _)? = conn.currentPath?.remoteEndpoint {
                        ip = ipv4String(host)
                    }
                    conn.cancel()
                    once.resume(ip)
                case .failed, .cancelled:
                    conn.cancel()
                    once.resume(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                conn.cancel()
                once.resume(nil)
            }
        }
    }

    private static func ipv4String(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address):
            return address.rawValue.map(String.init).joined(separator: ".")
        case .name(let name, _):
            return name
        case .ipv6:
            return nil  // W2 speakers are reached over IPv4 on the LAN
        @unknown default:
            return nil
        }
    }
}
