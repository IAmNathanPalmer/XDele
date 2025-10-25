// ContentView.swift
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
import Security

enum Keychain {
    static func set(_ value: Data, key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: value
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: "Keychain", code: Int(status)) }
    }

    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum TokenStore {
    private static let accessKey  = "xdele.access_token"
    private static let refreshKey = "xdele.refresh_token"

    static var accessToken: String? {
        get { Keychain.get(accessKey).flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let v = newValue { try? Keychain.set(Data(v.utf8), key: accessKey) }
            else { Keychain.remove(accessKey) }
        }
    }

    static var refreshToken: String? {
        get { Keychain.get(refreshKey).flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let v = newValue { try? Keychain.set(Data(v.utf8), key: refreshKey) }
            else { Keychain.remove(refreshKey) }
        }
    }
}
