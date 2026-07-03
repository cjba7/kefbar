// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// Parsing for KEF getData responses.
///
/// A getData response is a JSON array whose first element carries a `"type"`
/// field; the value lives under the key *named by* that type. This is
/// deliberately type-key-agnostic (SPEC §5 refinement #1) so it handles
/// `i32_`, `string_`, `kefSpeakerStatus`, `kefPhysicalSource`, etc. uniformly —
/// the §5 table's stated `string_` type is wrong for status/source.
public enum KEFValue {
    /// First element dict of a getData response array.
    static func firstElement(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let array = obj as? [[String: Any]], let first = array.first else {
            throw KEFError.badResponse("unexpected getData shape")
        }
        return first
    }

    /// The value stored under the key named by the element's `"type"` field.
    static func typedValue(_ data: Data) throws -> Any {
        let element = try firstElement(data)
        guard let type = element["type"] as? String else {
            throw KEFError.badResponse("getData element missing \"type\"")
        }
        guard let value = element[type] else {
            throw KEFError.badResponse("getData element missing value for type \"\(type)\"")
        }
        return value
    }

    public static func int(_ data: Data) throws -> Int {
        let value = try typedValue(data)
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        throw KEFError.badResponse("expected integer value")
    }

    public static func string(_ data: Data) throws -> String {
        let value = try typedValue(data)
        if let s = value as? String { return s }
        throw KEFError.badResponse("expected string value")
    }
}
