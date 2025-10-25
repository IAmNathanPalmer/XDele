// Constants.swift
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

enum XD {
    static let clientID      = "TU9HNFgwekxmdEQ2YlYyUWN1aVQ6MTpjaQ"
    static let redirectURI   = "xdele://callback"  // <- make sure this is in X Dev Portal callbacks, they MUST be exactly the same
    static let scopes        = "tweet.read tweet.write tweet.moderate.write users.read offline.access"
    static let authHost      = "twitter.com"
    static let apiHost       = "api.x.com"
}
