// XAPI.swift
// XDele
// © 2025 Nathaniel Palmer (@IAmNathanPalmer)
// Licensed under the GNU AGPLv3
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// https://www.gnu.org/licenses/agpl-3.0.html

import Foundation

enum XAPIError: Error {
    case unauthorized
    case forbidden(String)
    case http(Int, String)
    case network(String)
    case missingToken
}

final class XAPI {
    static let shared = XAPI()
    private init() {}

    private func bearer() throws -> String {
        guard let t = TokenStore.accessToken else { throw XAPIError.missingToken }
        return t
    }

    private func makeURL(path: String, query: [URLQueryItem]? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host   = XD.apiHost
        c.path   = path.hasPrefix("/") ? path : "/\(path)"
        c.queryItems = query
        return c.url!
    }

    func getMe() async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: makeURL(path: "/2/users/me"))
        req.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw XAPIError.network("No HTTP response") }
        if http.statusCode == 401 { throw XAPIError.unauthorized }
        if http.statusCode >= 400 { throw XAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "") }
        return (data, http)
    }

    // returns (httpResponse, bodyText) even on error
    func deleteTweet(id: String) async throws -> (HTTPURLResponse, String) {
        var req = URLRequest(url: makeURL(path: "/2/tweets/\(id)"))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw XAPIError.network("No HTTP response")
            }

            let bodyText = String(data: data, encoding: .utf8) ?? ""

            switch http.statusCode {
            case 200...299:
                return (http, bodyText)
            case 401:
                throw XAPIError.unauthorized
            case 403:
                throw XAPIError.forbidden(bodyText)
            case 429:
                // instead of throwing generic .http, throw a dedicated .http with headers info still capturable
                throw XAPIError.http(429, bodyText)
            default:
                throw XAPIError.http(http.statusCode, bodyText)
            }
        } catch let e as URLError {
            throw XAPIError.network(e.localizedDescription)
        }
    }
}
