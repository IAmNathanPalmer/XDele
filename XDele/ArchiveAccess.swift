// ArchiveAccess.swift
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

import Cocoa

final class ArchiveAccess {
    private let bookmarkKey = "XDele.ArchiveFolderBookmark"

    func pickArchiveFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choose X Archive Folder"
        if p.runModal() == .OK, let url = p.url {
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            } catch {
                print("[WARN] Failed to save bookmark: \(error)")
            }
        }
    }

    func startAccess() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if url.startAccessingSecurityScopedResource() { return url }
        } catch {
            print("[WARN] Resolving bookmark failed: \(error)")
        }
        return nil
    }

    func stopAccess(_ url: URL?) {
        url?.stopAccessingSecurityScopedResource()
    }

    func enumerateDataFiles(in root: URL, handler: (URL) -> Void) {
        // Accept either the archive root (containing "data") OR the "data" folder itself.
        let dataDir: URL = {
            if root.lastPathComponent.lowercased() == "data" { return root }
            let candidate = root.appendingPathComponent("data", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            return root // fallback: scan root anyway
        }()

        guard let e = FileManager.default.enumerator(
            at: dataDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("[WARN] Could not open \(dataDir.path)")
            return
        }

        var hitAny = false
        for case let fileURL as URL in e {
            hitAny = true
            handler(fileURL)
        }
        if !hitAny {
            print("[WARN] Archive scan found no files under: \(dataDir.path)")
        }
    }
}
