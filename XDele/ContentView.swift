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
// See <https://www.gnu.org/licenses/agpl-3.0.html>.

import SwiftUI
import UniformTypeIdentifiers
import CommonCrypto   // for HMAC-SHA1 (OAuth 1.0a)

struct ContentView: View {
    // MARK: - Auth mode

    enum AuthMode: String, CaseIterable, Identifiable {
        case oauth1 = "OAuth 1.0a"
        case oauth2 = "OAuth 2.0"
        var id: String { rawValue }
    }

    @State private var authMode: AuthMode = .oauth1   // default

    // MARK: - Window size persistence (macOS 14+)
    @AppStorage("XD_winWidth")  private var storedWidth: Double  = 720
    @AppStorage("XD_winHeight") private var storedHeight: Double = 600

    // MARK: - User config

    // OAuth 1.0a credentials
    @State private var apiKey = ""                // consumer key
    @State private var apiSecret = ""             // consumer secret
    @State private var accessToken1 = ""          // OAuth1 access token
    @State private var accessTokenSecret1 = ""    // OAuth1 token secret

    // OAuth 2.0 user token (bearer)
    @State private var accessToken2 = ""          // OAuth2 user token

    // Common
    @State private var userId = ""
    @State private var archiveFolderPath = ""
    @State private var maxDeletes = "99"
    @State private var dryRun = true

    // Filters
    @State private var includeKeywords = ""
    @State private var excludeKeywords = ""
    @State private var onlyRepliesToOthers = true
    @State private var includeRetweets = false
    @State private var unlikeLikes = false

    // MARK: - UI state
    @State private var log = ""
    @State private var isRunning = false
    @State private var showFolderPicker = false

    // Progress
    @State private var totalIDs: Int = 0
    @State private var deletedSoFar: Int = 0
    @State private var startTime: Date? = nil

    // App Support paths
    private var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("XD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var tweetIdsFile: URL { appSupportDir.appendingPathComponent("ids_to_delete.txt") }
    private var likeIdsFile: URL  { appSupportDir.appendingPathComponent("likes_to_unlike.txt") }
    private var stateFile: URL    { appSupportDir.appendingPathComponent("x_delete_state.json") }

    // Computed progress
    var progress: Double { totalIDs == 0 ? 0 : Double(deletedSoFar) / Double(totalIDs) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            VStack(alignment: .leading, spacing: 12) {
                Group {
                    // Auth mode — Option A (label + picker with empty visible label)
                    HStack {
                        Text("Auth Mode:")
                        Picker("", selection: $authMode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }

                    // Auth-specific fields
                    if authMode == .oauth1 {
                        TextField("API Key (consumer key)", text: $apiKey).textFieldStyle(.roundedBorder)
                        SecureField("API Key Secret (consumer secret)", text: $apiSecret).textFieldStyle(.roundedBorder)
                        TextField("Access Token (OAuth 1.0a)", text: $accessToken1).textFieldStyle(.roundedBorder)
                        SecureField("Access Token Secret (OAuth 1.0a)", text: $accessTokenSecret1).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Access Token (OAuth 2.0 Bearer)", text: $accessToken2).textFieldStyle(.roundedBorder)
                    }

                    TextField("User ID (numeric)", text: $userId).textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        TextField("Folder with tweets*.js (archive’s data/ folder)", text: $archiveFolderPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { showFolderPicker = true }
                            .keyboardShortcut("o")
                    }
                    .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                        switch result {
                        case .success(let urls):
                            if let url = urls.first {
                                archiveFolderPath = url.path
                                appendLog("[INFO] Selected folder: \(url.path)")
                            }
                        case .failure(let err):
                            appendLog("[WARN] Folder chooser failed: \(err.localizedDescription)")
                        }
                    }

                    HStack {
                        TextField("Max deletes per hour", text: $maxDeletes)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Toggle("Dry Run (don’t actually delete)", isOn: $dryRun)
                    }
                }

                Group {
                    TextField("Include keywords (comma-separated)", text: $includeKeywords)
                        .textFieldStyle(.roundedBorder)
                    TextField("Exclude keywords (comma-separated)", text: $excludeKeywords)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Only replies to others", isOn: $onlyRepliesToOthers)
                    Toggle("Include retweets", isOn: $includeRetweets)
                    Toggle("Unlike liked posts", isOn: $unlikeLikes)
                }

                HStack(spacing: 10) {
                    Button(isRunning ? "Stop" : "Start") {
                        if isRunning {
                            isRunning = false
                        } else {
                            isRunning = true
                            Task { await runDeleter() }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear X data") { clearXData() }
                        .buttonStyle(.bordered)
                        .help("Remove queued IDs and state from Application Support/XD")
                }

                // Progress + ETA
                Group {
                    ProgressView(value: progress).frame(maxWidth: .infinity)
                    HStack {
                        Text("\(deletedSoFar)/\(totalIDs) (\(Int(progress*100))%)")
                            .font(.caption).monospacedDigit()
                        Spacer()
                        let (etaSec, rate) = computeETA()
                        Text("ETA ~ \(fmtETA(etaSec))  @ \(String(format: "%.1f", rate))/hr")
                            .font(.caption).monospacedDigit()
                    }
                }
                .padding(.vertical, 4)

                Divider()
                Text("Log").font(.headline)
                ScrollView {
                    Text(log)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 320)
            }
            .padding()
            .frame(minWidth: 600,
                   idealWidth: CGFloat(storedWidth),
                   maxWidth: .infinity,
                   minHeight: 400,
                   idealHeight: CGFloat(storedHeight),
                   maxHeight: .infinity)
            // macOS 14+ two-parameter onChange
            .onChange(of: size) { _, newSize in
                if newSize.width > 100 && newSize.height > 100 {
                    storedWidth = Double(newSize.width)
                    storedHeight = Double(newSize.height)
                }
            }
        }
    }

    // MARK: - Main loop

    func runDeleter() async {
        log = ""
        appendLog("[INFO] XD starting…")
        // Validate required fields per mode
        switch authMode {
        case .oauth1:
            guard !apiKey.isEmpty, !apiSecret.isEmpty,
                  !accessToken1.isEmpty, !accessTokenSecret1.isEmpty,
                  !userId.isEmpty else {
                appendLog("[FATAL] Missing OAuth 1.0a keys/tokens or user ID.")
                isRunning = false
                return
            }
        case .oauth2:
            guard !accessToken2.isEmpty, !userId.isEmpty else {
                appendLog("[FATAL] Missing OAuth 2.0 token or user ID.")
                isRunning = false
                return
            }
        }

        let capPerHour = max(1, Int(maxDeletes) ?? 99)
        var state = loadState()

        // Build queues if folder provided
        if !archiveFolderPath.isEmpty {
            do {
                try buildQueuesFromFolder(archiveFolderPath, myId: userId)
            } catch {
                appendLog("[WARN] Could not parse archive: \(error.localizedDescription)")
            }
        } else {
            appendLog("[INFO] No folder provided; using existing queues if present.")
        }

        var tweetQueue = loadQueue(tweetIdsFile)
        var likeQueue  = unlikeLikes ? loadQueue(likeIdsFile) : []

        // Initialize progress
        if state.initialTotal == nil || state.initialTotal == 0 {
            state.initialTotal = tweetQueue.count + likeQueue.count
            state.deletedTotal = 0
        }
        totalIDs = state.initialTotal ?? (tweetQueue.count + likeQueue.count)
        deletedSoFar = state.deletedTotal ?? 0
        startTime = Date()
        saveState(state)

        appendLog("[INFO] Queued: tweets/retweets=\(tweetQueue.count)\(unlikeLikes ? ", likes=\(likeQueue.count)" : "")")
        appendLog(String(format: "[INFO] Estimated time @ cap %d/hr: %.1f hours",
                         capPerHour,
                         totalIDs > 0 ? Double(totalIDs - deletedSoFar) / Double(capPerHour) : 0))

        // Deletion loop: process in tiny micro-batches (≤3) respecting hourly window
        while isRunning && ( !tweetQueue.isEmpty || !likeQueue.isEmpty ) {
            resetWindowIfNeeded(&state)

            if state.deletesThisHour >= capPerHour {
                saveState(state)
                await sleepUntilNextHour()
                continue
            }

            // pick up to 3 actions per micro-cycle
            let remainingThisHour = capPerHour - state.deletesThisHour
            var microBudget = min(3, remainingThisHour)

            // Process tweet deletions first, then likes
            while microBudget > 0 && (!tweetQueue.isEmpty || !likeQueue.isEmpty) {
                if !tweetQueue.isEmpty {
                    let id = tweetQueue.removeFirst()
                    let ok = await performTweetDelete(id: id)
                    if ok { incrementProgress(&state) }
                    saveQueue(tweetQueue, to: tweetIdsFile)
                    microBudget -= 1
                    if !isRunning { break }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                if unlikeLikes && !likeQueue.isEmpty && microBudget > 0 {
                    let likedId = likeQueue.removeFirst()
                    let ok = await performUnlike(tweetId: likedId)
                    if ok { incrementProgress(&state) }
                    saveQueue(likeQueue, to: likeIdsFile)
                    microBudget -= 1
                    if !isRunning { break }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            saveState(state)
            if state.deletesThisHour < capPerHour {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5m idle between micro-cycles
            }
        }

        appendLog("[INFO] Done or stopped.")
        isRunning = false
    }

    // MARK: - Actions

    func performTweetDelete(id: String) async -> Bool {
        if dryRun {
            appendLog("[DRY] Would delete \(id)")
            return true
        }
        guard let url = URL(string:"https://api.twitter.com/2/tweets/\(id)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        guard let header = buildAuthHeader(method: "DELETE", url: url) else {
            appendLog("[FATAL] Could not build auth header.")
            return false
        }
        req.setValue(header, forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            if http.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
               let dataObj = obj["data"] as? [String:Any],
               let deleted = dataObj["deleted"] as? Bool, deleted {
                appendLog("[OK] Deleted \(id)")
                return true
            }
            if http.statusCode == 429 {
                appendLog("[WARN] 429 rate-limited; backing off 15m")
                try? await Task.sleep(nanoseconds: 900_000_000_000)
            } else {
                appendLog("[WARN] Delete \(id) failed (HTTP \(http.statusCode))")
                if authMode == .oauth2 {
                    appendLog("[HINT] If using OAuth 2.0, this endpoint may require OAuth 1.0a user context.")
                }
            }
            return false
        } catch {
            appendLog("[WARN] Delete \(id) error: \(error.localizedDescription)")
            return false
        }
    }

    func performUnlike(tweetId: String) async -> Bool {
        if dryRun {
            appendLog("[DRY] Would unlike \(tweetId)")
            return true
        }
        guard let url = URL(string:"https://api.twitter.com/2/users/\(userId)/likes/\(tweetId)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        guard let header = buildAuthHeader(method: "DELETE", url: url) else {
            appendLog("[FATAL] Could not build auth header.")
            return false
        }
        req.setValue(header, forHTTPHeaderField: "Authorization")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            if http.statusCode == 200 || http.statusCode == 204 {
                appendLog("[OK] Unliked \(tweetId)")
                return true
            }
            if http.statusCode == 429 {
                appendLog("[WARN] 429 rate-limited on unlike; backing off 15m")
                try? await Task.sleep(nanoseconds: 900_000_000_000)
            } else {
                appendLog("[WARN] Unlike \(tweetId) failed (HTTP \(http.statusCode))")
                if authMode == .oauth2 {
                    appendLog("[HINT] If using OAuth 2.0, this endpoint may require OAuth 1.0a user context.")
                }
            }
            return false
        } catch {
            appendLog("[WARN] Unlike \(tweetId) error: \(error.localizedDescription)")
            return false
        }
    }

    // Build Authorization header based on current mode
    func buildAuthHeader(method: String, url: URL) -> String? {
        switch authMode {
        case .oauth1:
            return oauth1Header(
                method: method,
                url: url,
                consumerKey: apiKey,
                consumerSecret: apiSecret,
                token: accessToken1,
                tokenSecret: accessTokenSecret1
            )
        case .oauth2:
            return "Bearer \(accessToken2)"
        }
    }

    // MARK: - Archive parsing & queue building

    struct ArchiveItem: Codable {
        struct Tw: Codable {
            let id: String
            let in_reply_to_user_id: String?
            let full_text: String?
        }
        let tweet: Tw
    }

    struct LikeItem: Codable {
        struct Inner: Codable { let tweetId: String; let fullText: String? }
        let like: Inner
    }

    func buildQueuesFromFolder(_ folderPath: String, myId: String) throws {
        var tweetIDs = Set<String>()
        var likeIDs  = Set<String>()

        let includes = parseKeywords(includeKeywords)
        let excludes = parseKeywords(excludeKeywords)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "XD.InvalidFolder", code: 1)
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        let items = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)

        // TWEETS (posts/replies/retweets)
        let tweetFiles = items.filter { $0.lastPathComponent.lowercased().hasPrefix("tweets") && $0.pathExtension.lowercased() == "js" }
        var totalSeenTweets = 0
        for file in tweetFiles {
            let list: [ArchiveItem] = try parseArrayWrappedJSON(file, topKeyPrefix: "window.YTD.tweets.")
            totalSeenTweets += list.count
            for item in list {
                let t = item.tweet
                guard shouldKeepTweet(t, myId: myId, includes: includes, excludes: excludes) else { continue }
                tweetIDs.insert(t.id)
            }
        }
        appendLog("[INFO] Tweets scanned: \(totalSeenTweets); queued: \(tweetIDs.count)")

        // LIKES (optional)
        if unlikeLikes {
            let likeFiles = items.filter {
                let n = $0.lastPathComponent.lowercased()
                return (n.hasPrefix("likes") || n.hasPrefix("like") || n.hasPrefix("favorite") || n.hasPrefix("favourite"))
                    && $0.pathExtension.lowercased() == "js"
            }
            var totalSeenLikes = 0
            for file in likeFiles {
                let list: [LikeItem] = try parseArrayWrappedJSON(file, topKeyPrefix: "window.YTD.like.")
                totalSeenLikes += list.count
                for item in list {
                    // optionally keyword-filter likes if text exists
                    if let txt = item.like.fullText, !matchesIncludeExclude(text: txt, includes: includes, excludes: excludes) {
                        continue
                    }
                    likeIDs.insert(item.like.tweetId)
                }
            }
            appendLog("[INFO] Likes scanned: \(totalSeenLikes); queued: \(likeIDs.count)")
        }

        // Write queues
        try Array(tweetIDs).sorted().joined(separator: "\n").write(to: tweetIdsFile, atomically: true, encoding: .utf8)
        setFileOwnerOnlyPermissions(tweetIdsFile)
        if unlikeLikes {
            try Array(likeIDs).sorted().joined(separator: "\n").write(to: likeIdsFile, atomically: true, encoding: .utf8)
            setFileOwnerOnlyPermissions(likeIdsFile)
        }

        // Reset progress baselines
        var state = loadState()
        let newTotal = Array(tweetIDs).count + (unlikeLikes ? Array(likeIDs).count : 0)
        state.initialTotal = newTotal
        state.deletedTotal = 0
        saveState(state)
        totalIDs = newTotal
        deletedSoFar = 0
        startTime = Date()

        appendLog("[INFO] Queues written to \(appSupportDir.path)")
    }

    /// Generic parser for files like: window.YTD.tweets.part0 = [ ... ];
    func parseArrayWrappedJSON<T: Decodable>(_ url: URL, topKeyPrefix: String) throws -> [T] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        // find first '[' and last ']'
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]") else { return [] }
        let jsonStr = String(raw[start...end])
        let data = Data(jsonStr.utf8)
        return try JSONDecoder().decode([T].self, from: data)
    }

    func shouldKeepTweet(_ tw: ArchiveItem.Tw, myId: String, includes: [String], excludes: [String]) -> Bool {
        let text = tw.full_text ?? ""
        let isReply = (tw.in_reply_to_user_id != nil)
        let isReplyToOthers = (tw.in_reply_to_user_id != nil && tw.in_reply_to_user_id != myId)
        let isRetweet = text.hasPrefix("RT @")
        let isOriginal = (!isReply && !isRetweet)

        // Scope
        var scopeOK = true
        if onlyRepliesToOthers && !isReplyToOthers { scopeOK = false }
        if !includeRetweets && isRetweet { scopeOK = false }
        if !onlyRepliesToOthers && !includeRetweets && !isOriginal { /* allow originals */ }
        // If the user insists "only replies", originals should be excluded:
        if onlyRepliesToOthers && isOriginal { scopeOK = false }

        if !scopeOK { return false }
        return matchesIncludeExclude(text: text, includes: includes, excludes: excludes)
    }

    // MARK: - Keyword helpers

    func parseKeywords(_ s: String) -> [String] {
        s.split(separator: ",")
         .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
         .filter { !$0.isEmpty }
    }

    func matchesIncludeExclude(text: String, includes: [String], excludes: [String]) -> Bool {
        let t = text.lowercased()
        if !includes.isEmpty && !includes.contains(where: { t.contains($0) }) { return false }
        if !excludes.isEmpty &&  excludes.contains(where: { t.contains($0) }) { return false }
        return true
    }

    // MARK: - Queue I/O

    func loadQueue(_ url: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return (try? String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").map { String($0) }) ?? []
    }

    func saveQueue(_ ids: [String], to url: URL) {
        try? ids.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        setFileOwnerOnlyPermissions(url)
    }

    // MARK: - State & throttling

    struct DeleterState: Codable {
        var lastWindowStart: String?
        var deletesThisHour: Int
        var initialTotal: Int?
        var deletedTotal: Int?
    }

    func loadState() -> DeleterState {
        guard let d = try? Data(contentsOf: stateFile) else {
            return .init(lastWindowStart:nil, deletesThisHour:0, initialTotal:0, deletedTotal:0)
        }
        return (try? JSONDecoder().decode(DeleterState.self, from:d))
            ?? .init(lastWindowStart:nil, deletesThisHour:0, initialTotal:0, deletedTotal:0)
    }

    func saveState(_ s: DeleterState) {
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: stateFile) }
        setFileOwnerOnlyPermissions(stateFile)
    }

    func resetWindowIfNeeded(_ s: inout DeleterState) {
        let now = Date()
        if !sameHour(s.lastWindowStart, now) {
            let cal = Calendar.current
            let floor = cal.date(bySettingHour: cal.component(.hour, from: now), minute: 0, second: 0, of: now)!
            s.lastWindowStart = ISO8601DateFormatter().string(from: floor)
            s.deletesThisHour = 0
        }
    }

    func sameHour(_ iso: String?, _ now: Date) -> Bool {
        guard let iso = iso, let t = ISO8601DateFormatter().date(from: iso) else { return false }
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.year, .month, .day, .hour], from: t)
             == cal.dateComponents([.year, .month, .day, .hour], from: now)
    }

    func sleepUntilNextHour() async {
        let now = Date()
        let cal = Calendar.current
        let nextHour = cal.date(byAdding: .hour, value: 1, to: cal.date(bySetting: .minute, value: 0, of: now)!)!
        let secs = max(10, Int(nextHour.timeIntervalSinceNow))
        appendLog("[INFO] Hourly cap reached. Sleeping \(secs)s")
        try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
    }

    func incrementProgress(_ s: inout DeleterState) {
        s.deletesThisHour += 1
        s.deletedTotal = (s.deletedTotal ?? 0) + 1
        deletedSoFar = s.deletedTotal ?? 0
        totalIDs = max(totalIDs, deletedSoFar)
        saveState(s)
    }

    func computeETA() -> (TimeInterval, Double) {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let ratePerHour = elapsed > 0 ? (Double(deletedSoFar) / elapsed) * 3600.0 : 0
        let remaining = max(0, totalIDs - deletedSoFar)
        let etaSec = ratePerHour > 0 ? (Double(remaining) / ratePerHour) * 3600.0 : 0
        return (etaSec, ratePerHour)
    }

    func fmtETA(_ seconds: TimeInterval) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds <= 0 { return "–" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" } else { return "\(m)m" }
    }

    // MARK: - Clear data & perms

    func clearXData() {
        var removed: [String] = []
        [tweetIdsFile, likeIdsFile, stateFile].forEach { url in
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                removed.append(url.lastPathComponent)
            }
        }
        appendLog(removed.isEmpty ? "[INFO] No X data to clear."
                  : "[INFO] Cleared: \(removed.joined(separator: ", "))")
        totalIDs = 0; deletedSoFar = 0; startTime = nil
    }

    func setFileOwnerOnlyPermissions(_ url: URL) {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: Int16(0o600))]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)
    }

    // MARK: - Logging

    func appendLog(_ s: String) { DispatchQueue.main.async { log.append(s + "\n") } }

    // MARK: - OAuth1 signer

    func oauth1Header(method: String,
                      url: URL,
                      queryParams: [String: String] = [:],
                      bodyParams: [String: String] = [:],
                      consumerKey: String,
                      consumerSecret: String,
                      token: String,
                      tokenSecret: String) -> String {

        func pct(_ s: String) -> String {
            var cs = CharacterSet.urlQueryAllowed
            cs.remove(charactersIn: ":#[]@!$&'()*+,;=") // strict RFC 3986
            return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
        }

        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let timestamp = String(Int(Date().timeIntervalSince1970))

        var oauthParams: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_nonce": nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": timestamp,
            "oauth_token": token,
            "oauth_version": "1.0"
        ]

        // Signature params = query + body + oauth
        var sigParams = queryParams.merging(bodyParams) { $1 }.merging(oauthParams) { $1 }
        let paramString = sigParams
            .map { (pct($0.key), pct($0.value)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")

        let baseURL = URL(string: "\(url.scheme!)://\(url.host!)\(url.path)")!
        let baseString = [
            method.uppercased(),
            pct(baseURL.absoluteString),
            pct(paramString)
        ].joined(separator: "&")

        let signingKey = "\(pct(consumerSecret))&\(pct(tokenSecret))"

        // HMAC-SHA1(baseString, signingKey)
        let keyData = signingKey.data(using: .utf8)!
        let msgData = baseString.data(using: .utf8)!
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            msgData.withUnsafeBytes { msgBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyBytes.baseAddress, keyData.count,
                       msgBytes.baseAddress, msgData.count,
                       &hmac)
            }
        }
        let sig = Data(hmac).base64EncodedString()
        oauthParams["oauth_signature"] = sig

        // Build final header with only oauth_* params
        let header = "OAuth " + oauthParams
            .map { (pct($0.key), pct($0.value)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\"\($0.1)\"" }
            .joined(separator: ", ")

        return header
    }
}
