// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Darwin
import Foundation

/// A speaker found on the LAN by discovery (SPEC §6). Distinct from a configured
/// `Speaker`: it carries only what a probe can learn, and is never persisted here.
public struct DiscoveredSpeaker: Equatable {
    public let mac: String        // stable identity key
    public let host: String       // IP it answered on
    public let name: String
    public let model: String
    public let firmware: String
    public let maxVolume: Int

    public init(mac: String, host: String, name: String, model: String,
                firmware: String, maxVolume: Int) {
        self.mac = mac
        self.host = host
        self.name = name
        self.model = model
        self.firmware = firmware
        self.maxVolume = maxVolume
    }
}

/// LAN discovery: Bonjour-first with a subnet-sweep fallback, each hit confirmed
/// by a contract probe (SPEC §6). This file implements the contract probe and the
/// subnet sweep; Bonjour (NWBrowser over the confirmed `_airplay._tcp` type) layers
/// on top and reuses `probe`.
public enum Discovery {

    // MARK: - Contract probe

    /// Confirm a host is a KEF W2 by reading its MAC (the shape/values are pinned),
    /// then fill in model/name/maxVolume/firmware. Returns nil if it isn't a KEF or
    /// doesn't answer within `timeout`. Cheap and safe to run against arbitrary IPs.
    public static func probe(host: String, timeout: TimeInterval = 0.4) async -> DiscoveredSpeaker? {
        let client = KEFClient(host: host, timeout: timeout)
        guard let mac = try? await client.mac(), isMACAddress(mac) else { return nil }

        // Best-effort detail fetch; an individual miss shouldn't drop a real speaker.
        let name = (try? await client.deviceName()) ?? ""
        let mf = (try? await client.modelFirmware()) ?? (model: "", firmware: "")
        let maxVolume = (try? await client.maxVolume()) ?? 100

        return DiscoveredSpeaker(
            mac: mac, host: host, name: name,
            model: mf.model, firmware: mf.firmware, maxVolume: maxVolume)
    }

    /// True for a `xx:xx:xx:xx:xx:xx` MAC (case-insensitive hex).
    static func isMACAddress(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 6 && parts.allSatisfy { part in
            part.count == 2 && part.allSatisfy(\.isHexDigit)
        }
    }

    // MARK: - Subnet sweep (fallback)

    /// Probe every host on the local /24 of each active IPv4 interface, with bounded
    /// concurrency. A full /24 finishes in ~1-2s (SPEC §6).
    public static func subnetSweep(concurrency: Int = 64, timeout: TimeInterval = 0.4) async
        -> [DiscoveredSpeaker]
    {
        await probeHosts(localSubnetHosts(), concurrency: concurrency, timeout: timeout)
    }

    /// Probe a list of hosts concurrently, at most `concurrency` in flight.
    static func probeHosts(_ hosts: [String], concurrency: Int, timeout: TimeInterval) async
        -> [DiscoveredSpeaker]
    {
        var found: [DiscoveredSpeaker] = []
        var iterator = hosts.makeIterator()

        await withTaskGroup(of: DiscoveredSpeaker?.self) { group in
            var inFlight = 0
            for _ in 0..<max(1, concurrency) {
                guard let host = iterator.next() else { break }
                group.addTask { await probe(host: host, timeout: timeout) }
                inFlight += 1
            }
            while inFlight > 0 {
                let result = await group.next() ?? nil
                inFlight -= 1
                if let speaker = result { found.append(speaker) }
                if let host = iterator.next() {
                    group.addTask { await probe(host: host, timeout: timeout) }
                    inFlight += 1
                }
            }
        }
        return found
    }

    /// Candidate host IPs on the local /24 of each active interface (excluding our
    /// own address). Assumes /24, which covers home LANs (SPEC §6).
    static func localSubnetHosts() -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for iface in activeIPv4Interfaces() {
            for candidate in subnetHosts(of: iface.ip) where seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    /// The `.1`–`.254` hosts of the /24 containing `ip`, excluding `ip` itself.
    static func subnetHosts(of ip: String) -> [String] {
        let octets = ip.split(separator: ".")
        guard octets.count == 4 else { return [] }
        let prefix = "\(octets[0]).\(octets[1]).\(octets[2])."
        return (1...254).map { prefix + String($0) }.filter { $0 != ip }
    }

    /// Active, non-loopback, non-link-local IPv4 interfaces -> their addresses.
    static func activeIPv4Interfaces() -> [(ip: String, mask: String)] {
        var result: [(ip: String, mask: String)] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor = ifaddrPtr
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = entry.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                  (flags & UInt32(IFF_LOOPBACK)) == 0,
                  let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            let ip = numericHost(addr)
            guard !ip.isEmpty, !ip.hasPrefix("169.254") else { continue }
            let mask = entry.pointee.ifa_netmask.map(numericHost) ?? "255.255.255.0"
            result.append((ip, mask))
        }
        return result
    }

    /// Render a sockaddr as a numeric host string.
    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = getnameinfo(
            addr, socklen_t(addr.pointee.sa_len),
            &buffer, socklen_t(buffer.count),
            nil, 0, NI_NUMERICHOST)
        return rc == 0 ? String(cString: buffer) : ""
    }

    // MARK: - Orchestration (Bonjour-first, subnet fallback — SPEC §6)

    /// Discover KEF W2 speakers on the LAN: browse `_airplay._tcp` and contract-probe
    /// the hits; if Bonjour yields nothing, fall back to a subnet sweep. Deduplicated
    /// by MAC. Never writes config (SPEC §11).
    public static func discover(bonjourTimeout: TimeInterval = 2.0,
                                probeTimeout: TimeInterval = 0.4) async -> [DiscoveredSpeaker] {
        let bonjourHosts = await BonjourBrowser.browseKEFAddresses(timeout: bonjourTimeout)
        let viaBonjour = await probeHosts(bonjourHosts, concurrency: 16, timeout: probeTimeout)
        if !viaBonjour.isEmpty {
            return dedupByMAC(viaBonjour)
        }
        return dedupByMAC(await subnetSweep(timeout: probeTimeout))
    }

    /// One entry per MAC, ordered by host address.
    static func dedupByMAC(_ speakers: [DiscoveredSpeaker]) -> [DiscoveredSpeaker] {
        var seen: Set<String> = []
        var result: [DiscoveredSpeaker] = []
        for speaker in speakers.sorted(by: { $0.host < $1.host }) {
            if seen.insert(speaker.mac.uppercased()).inserted {
                result.append(speaker)
            }
        }
        return result
    }
}
