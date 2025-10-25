// RateLimiter.swift
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

struct RateLimitInfo {
    let limit: Int
    let remaining: Int
    let reset: Date
}

enum RateLimiter {
    static func parse(from resp: HTTPURLResponse) -> RateLimitInfo? {
        guard
            let lim = resp.value(forHTTPHeaderField: "x-rate-limit-limit").flatMap(Int.init),
            let rem = resp.value(forHTTPHeaderField: "x-rate-limit-remaining").flatMap(Int.init),
            let rstStr = resp.value(forHTTPHeaderField: "x-rate-limit-reset"),
            let rst = TimeInterval(rstStr)
        else { return nil }
        return RateLimitInfo(limit: lim, remaining: rem, reset: Date(timeIntervalSince1970: rst))
    }

    static func logETA(queueRemaining: Int, info: RateLimitInfo) {
        let now = Date()
        let secToReset = max(0, info.reset.timeIntervalSince(now))

        // Consume current window, then whole windows of size = limit
        var left = queueRemaining
        var windows = 0
        left -= max(0, info.remaining)
        while left > 0 {
            left -= info.limit
            windows += 1
        }

        let totalSeconds = secToReset + (Double(windows) * max(60.0, 900.0)) // assume ≥15min per window; conservative
        let hours = totalSeconds / 3600.0
        let days  = hours / 24.0
        print("[INFO] Rate: \(info.remaining)/\(info.limit) left; resets \(info.reset)")
        print("[INFO] ETA for \(queueRemaining) deletes: ~\(String(format: "%.1f", hours)) hours (~\(String(format: "%.1f", days)) days)")
    }

    static func paceIfNeeded(info: RateLimitInfo) async {
        if info.remaining <= 0 {
            let wait = max(0, info.reset.timeIntervalSinceNow) + 1
            let ns = UInt64(wait * 1_000_000_000)
            print("[INFO] Rate limit exhausted. Sleeping ~\(String(format: "%.0f", wait))s until reset...")
            try? await Task.sleep(nanoseconds: ns)
        } else {
            // Gentle spacing to avoid burst—optional. Adjust if you want faster bursts on higher tiers.
            try? await Task.sleep(nanoseconds: 350_000_000) // ~0.35s
        }
    }
}
