// DeletionViewModel.swift
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
import Combine

// Track run state so the Start button can flip to Pause/Resume
enum JobState {
    case idle
    case running
    case paused
}

@MainActor
final class DeletionViewModel: ObservableObject {

    // MARK: - Published UI state

    @Published private(set) var jobState: JobState = .idle

    @Published private(set) var progressCount: Int = 0
    @Published private(set) var progressTotal: Int = 0

    // status flags for the pretty pills
    @Published private(set) var isSignedIn: Bool = (TokenStore.accessToken != nil)
    @Published private(set) var archiveLoaded: Bool = false

    // last few log lines that the UI shows
    @Published private(set) var visibleLog: String = ""

    // user toggles
    @Published var dryRun: Bool = true

    // internal control flags for pause/cancel
    private var pauseFlag = false
    private var cancelFlag = false

    // This is our bridge to the lower-level logic
    private let deleter = Deleter()

    // The queued tweet IDs to process
    private var queueIDs: [String] = []

    // internal full rolling buffer. We won't publish every character append,
    // we rebuild visibleLog from the tail each time.
    private var logLines: [String] = []

    // how many lines to surface in UI
    private let maxVisibleLines = 5

    // MARK: - private helpers

    private func pushLog(_ line: String) {
        logLines.append(line)

        // don't let unbounded memory blow up in a 10k tweet delete
        if logLines.count > 5000 {
            logLines.removeFirst(logLines.count - 5000)
        }

        // surface only tail N lines to UI
        let tail = logLines.suffix(maxVisibleLines)
        visibleLog = tail.joined(separator: "\n")

        // also print to console (full history for nerds / debugging)
        print(line)
    }

    private func setSignedInState() {
        isSignedIn = (TokenStore.accessToken != nil)
    }

    // MARK: - Public actions exposed to ContentView

    func signIn() {
        pushLog("[INFO] Starting sign-in…")
        deleter.signIn { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.setSignedInState()
                    self?.pushLog("[INFO] Sign-in complete.")
                case .failure(let err):
                    self?.pushLog("[WARN] Sign-in failed: \(err.localizedDescription)")
                }
            }
        }
    }

    func signOut() {
        TokenStore.accessToken = nil
        TokenStore.refreshToken = nil
        setSignedInState()
        pushLog("[INFO] Signed out and cleared stored tokens.")
    }

    func pickArchiveFolder() {
        deleter.pickArchiveFolder()
        pushLog("[INFO] Archive folder selected.")
    }

    func loadIDs() {
        let ids = deleter.loadIDsFromArchive()
        self.queueIDs = ids
        self.progressTotal = ids.count
        self.progressCount = 0
        self.archiveLoaded = !ids.isEmpty

        if ids.isEmpty {
            pushLog("[WARN] Loaded 0 IDs. Did you pick the UNZIPPED archive root?")
        } else {
            pushLog("[INFO] Loaded \(ids.count) IDs from archive.")
        }
    }

    func startOrPauseOrResume() {
        switch jobState {
        case .idle:
            startDeletion()
        case .running:
            pauseDeletion()
        case .paused:
            resumeDeletion()
        }
    }

    func cancelDeletion() {
        pushLog("[INFO] Cancelling…")
        cancelFlag = true
        pauseFlag = false
    }

    // MARK: - Internal state changes

    private func startDeletion() {
        guard !queueIDs.isEmpty else {
            pushLog("[WARN] No IDs queued; did you load or select anything?")
            return
        }

        guard isSignedIn else {
            pushLog("[WARN] Please sign in first.")
            return
        }

        pushLog(dryRun
                ? "[INFO] Dry run starting…"
                : "[INFO] Deletion starting…")

        jobState = .running
        pauseFlag = false
        cancelFlag = false
        progressCount = 0

        // run the worker loop in background
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.workerLoop()
        }
    }

    private func pauseDeletion() {
        pushLog("[INFO] Pausing…")
        pauseFlag = true
        jobState = .paused
    }

    private func resumeDeletion() {
        pushLog("[INFO] Resuming…")
        pauseFlag = false
        jobState = .running
    }

    // MARK: - Worker loop

    private func workerLoop() async {
        for (i, id) in queueIDs.enumerated() {

            if cancelFlag { break }

            while pauseFlag && !cancelFlag {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
            if cancelFlag { break }

            await MainActor.run {
                self.pushLog("[INFO] Processing \(id)…")
            }

            // do one delete (or log-only if dry run)
            let resultLine = await deleteSingle(id: id, dryRun: dryRun)

            await MainActor.run {
                self.pushLog(resultLine)
                self.progressCount = i + 1
            }
        }

        await MainActor.run {
            self.pushLog("[INFO] Complete. \(self.progressCount)/\(self.progressTotal) processed.")
            self.jobState = .idle
            self.pauseFlag = false
            self.cancelFlag = false
        }
    }

    // MARK: - One-tweet unit of work

    private func deleteSingle(id: String, dryRun: Bool) async -> String {
        if dryRun {
            // only simulate instead of calling API
            return "[DRY] Would delete \(id)"
        }
        let result = await deleter.deleteSingleTweet(id: id)
        return result
    }
}
