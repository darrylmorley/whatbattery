import SwiftUI
import AppKit
import WhatBatteryCore
import WhatBatteryAppKit

/// The in-app "update available" banner, shown at the top of the main window's
/// This Mac tab. Tracks the installer's live state through download, verify, and
/// install. Free feature.
struct UpdateBanner: View {
    let update: AvailableUpdate
    @ObservedObject private var installer = Installer.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .scaledFont(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("WhatBattery \(update.version) is available")
                    .scaledFont(.callout, weight: .bold)
                statusLine
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch installer.state {
        case .idle:
            Text("You're on \(AppInfo.version)")
        case .downloading:
            Text("Downloading…")
        case .verifying:
            Text("Verifying signature…")
        case .installing:
            Text("Installing, WhatBattery will relaunch")
        case .failed(let message):
            Text("Install failed: \(message)").foregroundStyle(.red)
        case .blocked(let message):
            Text(message).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch installer.state {
        case .idle, .failed:
            HStack(spacing: 6) {
                Button("View release") {
                    NSWorkspace.shared.open(update.url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if update.downloadURL != nil {
                    Button("Install update") {
                        Installer.shared.install(update)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        case .blocked:
            // Self-update can't run here; only offer the manual download path.
            Button("View release") {
                NSWorkspace.shared.open(update.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .downloading, .verifying, .installing:
            ProgressView().controlSize(.small)
        }
    }
}
