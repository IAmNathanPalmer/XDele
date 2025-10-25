// PKCEAuth.swift
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
import AppKit
import AuthenticationServices
import CryptoKit

private extension Data {
    var b64url: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct PKCE {
    let verifier: String
    let challenge: String
    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let v = Data(bytes).b64url
        verifier = v
        let c = Data(SHA256.hash(data: Data(v.utf8))).b64url
        challenge = c
    }
}

struct TokenResponse: Decodable {
    let token_type: String
    let access_token: String
    let expires_in: Int?
    let scope: String?
    let refresh_token: String?
}

final class OAuth2PKCE: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var currentPKCE: PKCE?
    private var state: String?

    // MARK: - ASWebAuthenticationPresentationContextProviding
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.mainWindow ?? NSApplication.shared.windows.first ?? NSApp.keyWindow ?? NSWindow()
    }

    // MARK: - Public API
    func startLogin(completion: @escaping (Result<Void, Error>) -> Void) {
        let pkce = PKCE()
        currentPKCE = pkce
        let state = UUID().uuidString
        self.state = state

        var c = URLComponents()
        c.scheme = "https"

        // Prefer a working host. I trust "twitter.com" more than "x.com",
        // because some networks can't resolve x.com reliably.
        let authHosts = [XD.authHost, "twitter.com"]
        c.host = authHosts.last        // ends up as "twitter.com"

        c.path = "/i/oauth2/authorize"
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: XD.clientID),
            .init(name: "redirect_uri", value: XD.redirectURI),
            .init(name: "scope", value: XD.scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]

        let url = c.url!
        print("[AUTH] Authorize URL:", url.absoluteString)

        let sess = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: URL(string: XD.redirectURI)?.scheme ?? "xdele"
        ) { [weak self] cbURL, err in
            guard let self else {
                completion(.failure(err ?? NSError(domain: "Auth", code: -1)))
                return
            }
            guard err == nil, let cbURL else {
                // --- Add this diagnostic logging ---
                if let e = err as? URLError {
                    print("[AUTH] ASWebAuth error: \(e.code.rawValue) \(e.code)")
                } else if let e = err {
                    print("[AUTH] ASWebAuth error: \(e.localizedDescription)")
                } else {
                    print("[AUTH] ASWebAuth error: Unknown (no NSError provided)")
                }
                // -----------------------------------
                completion(.failure(err ?? NSError(domain: "Auth", code: -1)))
                return
            }
            // print after cbURL is wrapped
            print("[AUTH] Callback URL: \(cbURL.absoluteString)")
            guard
                let comps  = URLComponents(url: cbURL, resolvingAgainstBaseURL: false),
                let code   = comps.queryItems?.first(where: { $0.name == "code" })?.value,
                let stateR = comps.queryItems?.first(where: { $0.name == "state" })?.value,
                stateR == state
            else {
                completion(.failure(NSError(domain: "Auth", code: -2,
                                            userInfo: [NSLocalizedDescriptionKey: "State mismatch"])))
                return
            }

            Task { [weak self] in
                do {
                    try await self?.exchange(code: code, verifier: pkce.verifier)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        sess.prefersEphemeralWebBrowserSession = true
        sess.presentationContextProvider = self
        sess.start()
        session = sess
    }

    /// Async wrapper so you can `await` sign-in (for Swift 6 no-semaphore style).
    func startLoginAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.startLogin { result in
                continuation.resume(with: result)
            }
        }
    }

    func refreshIfNeeded() async throws {
        guard let rt = TokenStore.refreshToken else { return }
        let body = [
            "grant_type": "refresh_token",
            "client_id": XD.clientID,
            "refresh_token": rt
        ]
        let (data, resp) = try await performTokenRequest(body)
        guard resp.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print("[AUTH] Refresh failed \(resp.statusCode): \(bodyStr)")
            throw handleBadToken(data, resp)
        }
        let tok = try decodeToken(data)
        save(tok)
    }

    // MARK: - Token exchange helpers
    private func form(_ dict: [String: String]) -> Data {
        dict.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
        }
        .joined(separator: "&")
        .data(using: .utf8)!
    }

    private func tokenRequest(body: [String: String]) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://\(XD.apiHost)/2/oauth2/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = form(body)
        return r
    }

    private func decodeToken(_ data: Data) throws -> TokenResponse {
        try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func save(_ tok: TokenResponse) {
        TokenStore.accessToken  = tok.access_token
        if let rt = tok.refresh_token { TokenStore.refreshToken = rt }
    }

    private func handleBadToken(_ data: Data, _ resp: HTTPURLResponse) -> Error {
        let body = String(data: data, encoding: .utf8) ?? ""
        return NSError(
            domain: "Auth",
            code: resp.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Token error \(resp.statusCode): \(body)"]
        )
    }

    private func performTokenRequest(_ body: [String:String]) async throws -> (Data, HTTPURLResponse) {
        // Try primary host (XD.apiHost), then fall back to api.twitter.com if DNS says "host not found".
        let hosts = [XD.apiHost, "api.twitter.com"]
        var lastError: Error?

        for host in hosts {
            var r = URLRequest(url: URL(string: "https://\(host)/2/oauth2/token")!)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = form(body)

            do {
                let (data, resp) = try await URLSession.shared.data(for: r)
                if let http = resp as? HTTPURLResponse {
                    return (data, http)
                } else {
                    lastError = NSError(domain: "Auth", code: -3, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
                }
            } catch let e as URLError {
                lastError = e
                if e.code == .cannotFindHost || e.code == .dnsLookupFailed {
                    print("[AUTH] Host \(host) not found; trying next…")
                    continue
                } else { break }
            } catch {
                lastError = error
                break
            }
        }
        throw lastError ?? NSError(domain: "Auth", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown token request error"])
    }
    
    private func exchange(code: String, verifier: String) async throws {
        let body = [
            "grant_type": "authorization_code",
            "client_id": XD.clientID,
            "code": code,
            "redirect_uri": XD.redirectURI,
            "code_verifier": verifier
        ]

        let (data, resp) = try await performTokenRequest(body)
        guard resp.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print("[AUTH] Exchange failed \(resp.statusCode): \(bodyStr)")
            throw handleBadToken(data, resp)
        }

        let tok = try decodeToken(data)
        save(tok)
    }
}
