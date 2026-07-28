import Foundation
import ServiceManagement
import os.log

/// Whether macOS starts WhatBattery when the user logs in.
///
/// More than a convenience: Pro's value is the history it records, and nothing
/// is recorded while the app is not running. Without this, someone who buys Pro,
/// quits, and comes back a month later finds an empty analyzer and no
/// explanation for it.
///
/// The system owns the real state (the user can flip it in System Settings >
/// General > Login Items), so `SMAppService.mainApp.status` is read back rather
/// than mirrored into `UserDefaults`, which would drift.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    private static let logger = Logger(subsystem: "app.whatbattery.whatbattery", category: "LaunchAtLogin")

    /// True when macOS will launch the app at login.
    @Published private(set) var isEnabled = false

    /// The user switched the login item off in System Settings. macOS keeps it
    /// off until they re-enable it there; registering again from here does
    /// nothing, so the UI has to say so instead of silently failing.
    @Published private(set) var requiresApproval = false

    /// Why the last register / unregister failed, for the settings row to show.
    @Published private(set) var lastError: String?

    private init() {
        refresh()
    }

    /// Re-reads the system's state. Worth calling whenever settings appear,
    /// since this can be changed outside the app.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func set(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fails when the binary is not inside a real .app bundle (a
            // `swift run` build) or the bundle sits somewhere macOS will not
            // accept as a login item, such as a quarantined Downloads copy.
            Self.logger.error("launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        refresh()
    }
}
