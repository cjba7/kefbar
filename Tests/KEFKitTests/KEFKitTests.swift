// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import XCTest

@testable import KEFKit

// MARK: - Value parsing (SPEC §5 refinement #1: value under the "type"-named key)

final class KEFValueTests: XCTestCase {
    func testInt_i32() throws {
        XCTAssertEqual(try KEFValue.int(Data(#"[{"type":"i32_","i32_":40}]"#.utf8)), 40)
    }

    func testInt_zero() throws {
        XCTAssertEqual(try KEFValue.int(Data(#"[{"type":"i32_","i32_":0}]"#.utf8)), 0)
    }

    func testString_string_() throws {
        let data = Data(#"[{"type":"string_","string_":"84:17:15:03:CD:9E"}]"#.utf8)
        XCTAssertEqual(try KEFValue.string(data), "84:17:15:03:CD:9E")
    }

    func testString_customKey_speakerStatus() throws {
        // Real shape: type key is kefSpeakerStatus, NOT string_ (the §5 table is wrong).
        let data = Data(#"[{"kefSpeakerStatus":"powerOn","type":"kefSpeakerStatus"}]"#.utf8)
        XCTAssertEqual(try KEFValue.string(data), "powerOn")
    }

    func testString_customKey_physicalSource() throws {
        let data = Data(#"[{"kefPhysicalSource":"wifi","type":"kefPhysicalSource"}]"#.utf8)
        XCTAssertEqual(try KEFValue.string(data), "wifi")
    }

    func testBadShapes_throw() {
        XCTAssertThrowsError(try KEFValue.int(Data("{}".utf8)))
        XCTAssertThrowsError(try KEFValue.int(Data("[]".utf8)))
        XCTAssertThrowsError(try KEFValue.int(Data(#"[{"type":"i32_"}]"#.utf8)))  // no value
        XCTAssertThrowsError(try KEFValue.int(Data(#"[{"i32_":5}]"#.utf8)))       // no type
    }
}

// MARK: - setData envelope (SPEC §5)

final class SetDataEnvelopeTests: XCTestCase {
    func testVolumeBody() throws {
        let obj = try JSONSerialization.jsonObject(with: KEFClient.volumeBody(30)) as? [String: Any]
        XCTAssertEqual(obj?["path"] as? String, "player:volume")
        XCTAssertEqual(obj?["roles"] as? String, "value")
        let value = obj?["value"] as? [String: Any]
        XCTAssertEqual(value?["type"] as? String, "i32_")
        XCTAssertEqual(value?["i32_"] as? Int, 30)
    }

    func testVolumeValueJSON() throws {
        let obj = try JSONSerialization.jsonObject(
            with: Data(KEFClient.volumeValueJSON(20).utf8)) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "i32_")
        XCTAssertEqual(obj?["i32_"] as? Int, 20)
    }
}

// MARK: - Clamp + step bound (SPEC §8, §11)

final class ClampAndStepTests: XCTestCase {
    func testClampVolume() {
        XCTAssertEqual(Config.clampVolume(50, maxVolume: 100), 50)
        XCTAssertEqual(Config.clampVolume(150, maxVolume: 100), 100)
        XCTAssertEqual(Config.clampVolume(150, maxVolume: 80), 80)
        XCTAssertEqual(Config.clampVolume(-5, maxVolume: 100), 0)
        XCTAssertEqual(Config.clampVolume(0, maxVolume: 100), 0)
    }

    func testStepBound() {
        XCTAssertFalse(Config.isValidStep(0))
        XCTAssertTrue(Config.isValidStep(1))
        XCTAssertTrue(Config.isValidStep(5))
        XCTAssertTrue(Config.isValidStep(10))
        XCTAssertFalse(Config.isValidStep(11))
        XCTAssertFalse(Config.isValidStep(100))
        XCTAssertFalse(Config.isValidStep(-1))
    }
}

// MARK: - releasetext -> model + firmware (SPEC §5 refinement #2)

final class ModelInfoTests: XCTestCase {
    func testParse() {
        let (m, f) = ModelInfo.parseReleaseText("LSXII_V30137")
        XCTAssertEqual(m, "LSXII")
        XCTAssertEqual(f, "V30137")
    }

    func testAliases() {
        XCTAssertEqual(ModelInfo.parseReleaseText("LSX2_V27100").model, "LSXII")
        XCTAssertEqual(ModelInfo.parseReleaseText("LS50W2_V1").model, "LS50WII")
        XCTAssertEqual(ModelInfo.parseReleaseText("LSX2LT_V2").model, "LSXIILT")
    }

    func testNoUnderscore() {
        let (m, f) = ModelInfo.parseReleaseText("WEIRD")
        XCTAssertEqual(m, "WEIRD")
        XCTAssertEqual(f, "")
    }
}

// MARK: - Speaker resolution matrix (SPEC §11)

final class ResolutionTests: XCTestCase {
    let two = Config(speakers: [
        Speaker(id: "m1", name: "Study Desk", host: "10.0.0.1"),
        Speaker(id: "m2", name: "Living Room", host: "10.0.0.2"),
    ])

    func testHostAlwaysWins() {
        XCTAssertEqual(
            Config.resolve(config: two, host: "1.2.3.4", speakerName: "Study Desk"),
            .success(.adHocHost("1.2.3.4")))
    }

    func testSpeakerByName_caseInsensitive() {
        guard case .success(.configured(let s)) =
            Config.resolve(config: two, host: nil, speakerName: "living room")
        else { return XCTFail("expected configured") }
        XCTAssertEqual(s.id, "m2")
    }

    func testNotFound() {
        XCTAssertEqual(
            Config.resolve(config: two, host: nil, speakerName: "Nope"),
            .failure(.notFound("Nope")))
    }

    func testDefault() {
        var c = two
        c.defaultSpeakerId = "m1"
        guard case .success(.configured(let s)) =
            Config.resolve(config: c, host: nil, speakerName: nil)
        else { return XCTFail("expected configured") }
        XCTAssertEqual(s.id, "m1")
    }

    func testSoleSpeaker() {
        let c = Config(speakers: [Speaker(id: "x", name: "Only", host: "10.0.0.9")])
        guard case .success(.configured(let s)) =
            Config.resolve(config: c, host: nil, speakerName: nil)
        else { return XCTFail("expected configured") }
        XCTAssertEqual(s.id, "x")
    }

    func testAmbiguous() {
        XCTAssertEqual(
            Config.resolve(config: two, host: nil, speakerName: nil),
            .failure(.ambiguous(["Study Desk", "Living Room"])))
    }

    func testNoneConfigured() {
        XCTAssertEqual(
            Config.resolve(config: Config(), host: nil, speakerName: nil),
            .failure(.noneConfigured))
    }
}

// MARK: - Discovery (SPEC §6): MAC validation, subnet math, dedup

final class DiscoveryTests: XCTestCase {
    func testIsMACAddress() {
        XCTAssertTrue(Discovery.isMACAddress("84:17:15:03:CD:9E"))
        XCTAssertTrue(Discovery.isMACAddress("00:00:00:00:00:00"))
        XCTAssertFalse(Discovery.isMACAddress("84:17:15:03:CD"))     // 5 groups
        XCTAssertFalse(Discovery.isMACAddress("84-17-15-03-CD-9E"))  // wrong separator
        XCTAssertFalse(Discovery.isMACAddress("ZZ:17:15:03:CD:9E"))  // non-hex
        XCTAssertFalse(Discovery.isMACAddress("192.168.1.114"))
        XCTAssertFalse(Discovery.isMACAddress(""))
    }

    func testSubnetHosts() {
        let hosts = Discovery.subnetHosts(of: "192.168.1.106")
        XCTAssertEqual(hosts.count, 253)  // .1–.254 minus our own address
        XCTAssertFalse(hosts.contains("192.168.1.106"))
        XCTAssertTrue(hosts.contains("192.168.1.114"))
        XCTAssertTrue(hosts.contains("192.168.1.1"))
        XCTAssertTrue(hosts.contains("192.168.1.254"))
        XCTAssertFalse(hosts.contains("192.168.1.0"))    // network address excluded
        XCTAssertFalse(hosts.contains("192.168.1.255"))  // broadcast excluded
        XCTAssertTrue(Discovery.subnetHosts(of: "nonsense").isEmpty)
    }

    func testDedupByMAC() {
        let a = DiscoveredSpeaker(mac: "AA:BB:CC:DD:EE:01", host: "10.0.0.5",
                                  name: "A", model: "LSXII", firmware: "V1", maxVolume: 100)
        let aDup = DiscoveredSpeaker(mac: "aa:bb:cc:dd:ee:01", host: "10.0.0.9",
                                     name: "A2", model: "LSXII", firmware: "V1", maxVolume: 100)
        let b = DiscoveredSpeaker(mac: "AA:BB:CC:DD:EE:02", host: "10.0.0.2",
                                  name: "B", model: "LS50WII", firmware: "V1", maxVolume: 80)
        let out = Discovery.dedupByMAC([a, aDup, b])
        XCTAssertEqual(out.count, 2)                 // case-insensitive MAC dedup
        XCTAssertEqual(out.first?.host, "10.0.0.2")  // ordered by host
        XCTAssertTrue(out.contains { $0.mac == "AA:BB:CC:DD:EE:01" && $0.host == "10.0.0.5" })
    }
}

// MARK: - Event poll parsing (SPEC §5)

final class EventPollTests: XCTestCase {
    func testParseVolumeEvent() {
        let data = Data(#"[{"rowsEvents":[],"itemType":"update","itemValue":{"type":"i32_","i32_":35},"path":"player:volume"}]"#.utf8)
        XCTAssertEqual(KEFClient.parseEvents(data), [.volume(35)])
    }

    func testParseStatusEvent() {
        let data = Data(#"[{"itemValue":{"kefSpeakerStatus":"standby","type":"kefSpeakerStatus"},"path":"settings:/kef/host/speakerStatus"}]"#.utf8)
        XCTAssertEqual(KEFClient.parseEvents(data), [.status("standby")])
    }

    func testParseIgnoresUnknownPaths() {
        let data = Data(#"[{"itemValue":{"type":"i32_","i32_":10},"path":"player:volume"},{"itemValue":{"type":"i32_","i32_":5},"path":"some:/other"}]"#.utf8)
        XCTAssertEqual(KEFClient.parseEvents(data), [.volume(10)])
    }

    func testParseEmpty() {
        XCTAssertEqual(KEFClient.parseEvents(Data("[]".utf8)), [])
    }
}

// MARK: - Config atomic round-trip + lenient decode (SPEC §7)

final class ConfigRoundTripTests: XCTestCase {
    func testAtomicRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kefbar-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let cfg = Config(
            defaultSpeakerId: "m1", cliStep: 7,
            speakers: [
                Speaker(id: "m1", name: "Study Desk", host: "10.0.0.1", model: "LSXII",
                        maxVolume: 90, firmware: "V30137", lastSeen: "2026-07-02T10:00:00Z")
            ])
        try cfg.save(to: url)
        XCTAssertEqual(try Config.load(from: url), cfg)
    }

    func testLenientDecodeDefaults() throws {
        let cfg = try JSONDecoder().decode(Config.self, from: Data(#"{"speakers":[]}"#.utf8))
        XCTAssertEqual(cfg.version, 1)
        XCTAssertEqual(cfg.cliStep, 5)
        XCTAssertNil(cfg.defaultSpeakerId)
    }

    func testMissingFileReturnsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kefbar-none-\(UUID().uuidString)/config.json")
        XCTAssertEqual(try Config.load(from: url).speakers.count, 0)
    }
}
