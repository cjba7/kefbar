// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

/// A minimal HTTP result: the raw body and the status code.
public struct HTTPResponse {
    public let data: Data
    public let status: Int
}

/// Thin wrapper over native async `URLSession.data(for:)` (SPEC §8).
/// Maps transport failures to `KEFError.unreachable`.
public final class HTTP {
    private let session: URLSession

    public init(timeout: TimeInterval = 5.0) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        // Fail fast rather than wait for connectivity: a CLI/slider write should
        // error immediately if the speaker is off, not hang. (On macOS 15+, LAN
        // access also requires Local Network permission — see README.)
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    public func get(_ url: URL) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await perform(req)
    }

    public func postJSON(_ url: URL, body: Data) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return try await perform(req)
    }

    private func perform(_ req: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw KEFError.badResponse("non-HTTP response")
            }
            return HTTPResponse(data: data, status: http.statusCode)
        } catch let error as URLError {
            throw KEFError.unreachable("network error: \(error.localizedDescription)")
        }
    }
}
