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

import SwiftUI

// Little colored indicator pill
private struct StatusPill: View {
    let label: String
    let ok: Bool
    let extra: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)

            if let extra {
                Text(extra)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ok ? Color.green.opacity(0.4) : Color.red.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

struct ContentView: View {
    @StateObject private var vm = DeletionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header/status row
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        StatusPill(
                            label: vm.isSignedIn ? "Signed In" : "Not Signed In",
                            ok: vm.isSignedIn,
                            extra: vm.isSignedIn ? nil : nil
                        )

                        StatusPill(
                            label: vm.archiveLoaded ? "Archive Loaded" : "No Archive",
                            ok: vm.archiveLoaded,
                            extra: vm.archiveLoaded ? "\(vm.progressTotal) IDs" : nil
                        )
                    }

                    Text("XDele")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Delete your old tweets safely using your exported X archive. Dry Run mode lets you preview without deleting.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()

            // Auth / Archive controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button(vm.isSignedIn ? "Sign Out" : "Sign In") {
                        if vm.isSignedIn {
                            vm.signOut()
                        } else {
                            vm.signIn()
                        }
                    }

                    Button("Pick Archive") {
                        vm.pickArchiveFolder()
                    }

                    Button("Load IDs") {
                        vm.loadIDs()
                    }
                }
                .buttonStyle(.bordered)

                Toggle("Dry Run (don't actually delete)", isOn: $vm.dryRun)
                    .disabled(vm.jobState != .idle)
            }

            Divider()

            // Run controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Run")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button(
                        vm.jobState == .idle
                            ? "Start"
                            : vm.jobState == .running
                                ? "Pause"
                                : "Resume"
                    ) {
                        vm.startOrPauseOrResume()
                    }
                    .disabled(vm.progressTotal == 0 && vm.jobState == .idle)

                    Button("Cancel") {
                        vm.cancelDeletion()
                    }
                    .disabled(vm.jobState == .idle)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                Text("Progress: \(vm.progressCount)/\(vm.progressTotal)")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            // Log view
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Activity")
                    .font(.headline)

                ScrollView {
                    Text(vm.visibleLog.isEmpty ? "…" : vm.visibleLog)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(minHeight: 140, maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                )
            }

            Spacer()
        }
        .padding(20)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
