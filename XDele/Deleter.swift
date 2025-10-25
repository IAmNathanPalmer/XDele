// Deleter.swift
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

final class Deleter {
    private let auth = OAuth2PKCE()
    private let archive = ArchiveAccess()
    
    // Call this when the user hits “Sign in”
    func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
        auth.startLogin(completion: completion)
    }
    
    // Optional: preflight to confirm token works
    func testAuth() async {
        do {
            try await auth.refreshIfNeeded()
            let (_, http) = try await XAPI.shared.getMe()
            print("[INFO] Auth OK. User info fetched. Rate headers present? \(RateLimiter.parse(from: http) != nil)")
        } catch {
            print("[WARN] Auth test failed: \(error)")
        }
    }
    
    // Let user pick the unzipped archive folder once; we persist a bookmark
    func pickArchiveFolder() {
        archive.pickArchiveFolder()
    }
    
    // Example: Build an ID list from the archive; replace with your real parser
    func loadIDsFromArchive() -> [String] {
        guard let root = archive.startAccess() else {
            print("[WARN] No archive access (pick folder first).")
            return []
        }
        defer { archive.stopAccess(root) }
        
        var ids = Set<String>()
        
        // Walk data/ and parse files like tweets.js, tweets-part*.js, *.json
        archive.enumerateDataFiles(in: root) { url in
            let name = url.lastPathComponent.lowercased()
            
            // JS exports: window.YTD.tweets.part0 = [ ... ]
            if name.hasSuffix(".js") {
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   let json = stripYTDPrefix(text) {
                    extractIDs(fromJSON: json, into: &ids)
                }
                return
            }
            
            // Raw JSON arrays (some archives use .json)
            if name.hasSuffix(".json") {
                if let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8) {
                    extractIDs(fromJSON: text, into: &ids)
                }
                return
            }
        }
        
        let result = Array(ids)
        print("[INFO] Discovered \(result.count) tweet IDs from archive.")
        return result
    }
    
    // MARK: - Local helpers (keep these inside Deleter)
    
    /// Strips the `window.YTD.* = ` prefix and returns the JSON array text if present.
    private func stripYTDPrefix(_ js: String) -> String? {
        guard let start = js.firstIndex(of: "["),
              let end   = js.lastIndex(of: "]"),
              end > start
        else { return nil }
        return String(js[start...end])
    }
    
    /// Extracts tweet IDs from common YTD shapes into `ids`.
    private func extractIDs(fromJSON text: String, into ids: inout Set<String>) {
        guard let data = text.data(using: .utf8) else { return }
        
        // Try normal JSON parsing first
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for el in arr {
                guard let d = el as? [String: Any] else { continue }
                
                // Most common shape: { "tweet": { "id": "...", "id_str": "..." } }
                if let tw = d["tweet"] as? [String: Any] {
                    if let id = (tw["id_str"] as? String) ?? (tw["id"] as? String) {
                        ids.insert(id)
                    }
                    continue
                }
                
                // Flat variant: { "id_str": "...", ... }
                if let id = (d["id_str"] as? String) ?? (d["id"] as? String) {
                    ids.insert(id)
                }
            }
            return
        }
        
        // Fallback: regex for id fields if the structure is odd
        let pattern = #""id(?:_str)?"\s*:\s*"(\d+)""#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 2 {
                ids.insert(ns.substring(with: m.range(at: 1)))
            }
        }
    }
    
    func refreshAuthIfNeeded() async throws {
        try await auth.refreshIfNeeded()
    }
    
    func interactiveReauth() async throws {
        try await auth.startLoginAsync()
    }
    
    // MARK: - Single-tweet delete helper
    func deleteSingleTweet(id: String) async -> String {
        // helper to extract rate limit info even from errors
        func rateInfo(from http: HTTPURLResponse?) -> RateLimitInfo? {
            guard let http = http else { return nil }
            return RateLimiter.parse(from: http)
        }

        // inner function that tries once (no retry logic)
        func attemptDelete() async -> (ok: Bool, msg: String, info: RateLimitInfo?, code: Int?) {
            do {
                try await refreshAuthIfNeeded()
                let (http, _) = try await XAPI.shared.deleteTweet(id: id)

                // success path
                let rate = rateInfo(from: http)
                return (true, "[OK] Deleted \(id)", rate, http.statusCode)

            } catch XAPIError.unauthorized {
                // try interactive reauth and single retry inside here
                do {
                    try await interactiveReauth()
                } catch {
                    return (false,
                            "[FAIL] \(id) unauthorized; reauth failed: \(error)",
                            nil,
                            401)
                }

                do {
                    let (http2, _) = try await XAPI.shared.deleteTweet(id: id)
                    let rate2 = rateInfo(from: http2)
                    if (200...299).contains(http2.statusCode) {
                        return (true,
                                "[OK] Reauth delete \(id) (remaining \(rate2?.remaining ?? -1))",
                                rate2,
                                http2.statusCode)
                    } else {
                        return (false,
                                "[FAIL] Retry after re-auth still failed for \(id): HTTP \(http2.statusCode)",
                                rate2,
                                http2.statusCode)
                    }
                } catch {
                    return (false,
                            "[FAIL] Retry after re-auth still threw: \(prettyError(error))",
                            nil,
                            nil)
                }

            } catch {
                // non-401 failure
                return (false,
                        "[WARN] \(id) not deleted: \(prettyError(error))",
                        nil,
                        (error as? XAPIError).flatMap(httpCodeFromXAPIError))
            }
        }

        // First try
        let first = await attemptDelete()

        // If success, pace and done
        if first.ok {
            if let rate = first.info {
                await RateLimiter.paceIfNeeded(info: rate)
            } else {
                // fallback gentle spacing
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            return first.msg
        }

        // If we got a 429, try to respect reset header and retry once
        if first.code == 429 {
            // We cannot pull headers from the thrown error directly unless we capture them.
            // Let's do a manual cooldown based on RateLimiter logic:
            // We'll pessimistically sleep 60 seconds and try once more.
            // (If you're truly "0 quota ever", retry will just 429 again and we'll give up.)
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s

            let second = await attemptDelete()
            if second.ok {
                if let rate = second.info {
                    await RateLimiter.paceIfNeeded(info: rate)
                } else {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                return second.msg
            }

            // still not ok
            return second.msg + " [RATE-LIMITED]"
        }

        // normal failure, not 429
        return first.msg
    }

    // expose HTTP code if we threw XAPIError.http(_,_) above
    private func httpCodeFromXAPIError(_ err: XAPIError) -> Int? {
        switch err {
        case .http(let code, _): return code
        case .unauthorized: return 401
        case .forbidden: return 403
        default: return nil
        }
    }

    // make prettyError internal (same as before, keep this in Deleter)
    private func prettyError(_ error: Error) -> String {
        switch error {
        case XAPIError.unauthorized:
            return "401 Unauthorized (token / scope / refresh issue)"

        case XAPIError.forbidden(let body):
            return "403 Forbidden. Body=\(body)"

        case XAPIError.http(let code, let body):
            return "\(code) HTTP. Body=\(body)"

        case XAPIError.network(let msg):
            return "Network error: \(msg)"

        case XAPIError.missingToken:
            return "No access token in TokenStore"

        default:
            return error.localizedDescription
        }
    }

}
