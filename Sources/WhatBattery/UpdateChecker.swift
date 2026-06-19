// Self-hosted update checker. Free feature: polls the GitHub releases API for a
// newer WhatBattery and surfaces it (banner, alert, optional notification). No
// Pro symbols, so it ships in the public mirror.
import Foundation
import AppKit
import UserNotifications
import os.log
import WhatBatteryCore

struct AvailableUpdate: Equatable {
    let version: String
    let url: URL
    let downloadURL: URL?
    let notes: String?
}

/// Polls the GitHub releases API for newer versions of WhatBattery.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// Settings key: post a notification when a new version is found. Default on
    /// (absent reads as true), so existing users keep getting update notices.
    static let notifyKey = "notifyOnUpdates"

    private nonisolated static let log = Logger(subsystem: "app.whatbattery.whatbattery", category: "updates")
    private static let endpoint = AppInfo.latestReleaseAPI
    private static let pollInterval: TimeInterval = 6 * 60 * 60 // 6h
    private static let assetName = "WhatBattery.zip"

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheck: Date?

    private var timer: Timer?
    private var notifiedVersion: String?
    /// True while a modal alert is on screen. `runModal()` spins a nested run
    /// loop, so the launch / 6h timer check can complete and try to present a
    /// second alert on top of the first; this guard drops that second one.
    private var isPresentingAlert = false
    /// When a manual "Check for Updates" click arrives while a silent background
    /// check is in flight, set this so the in-flight result surfaces a visible
    /// alert instead of being silently swallowed.
    private var pendingVisibleCheck = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        check(silent: true)
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(silent: true) }
        }
    }

    /// Manually trigger a check. When `silent` is false, surfaces an alert for the
    /// "no update" case so the user gets feedback from the menu item.
    func check(silent: Bool) {
        if isChecking {
            // A check is already in flight. If the user explicitly asked for one,
            // upgrade the in-flight result to non-silent so they still get
            // feedback. Multiple manual clicks coalesce into one alert.
            if !silent { pendingVisibleCheck = true }
            return
        }
        isChecking = true
        pendingVisibleCheck = !silent

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WhatBattery/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isChecking = false
                self.lastCheck = Date()
                // If a manual click arrived during the in-flight check, this gets
                // surfaced. Reset for the next run.
                let visible = self.pendingVisibleCheck
                self.pendingVisibleCheck = false

                if let error {
                    Self.log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                    if visible { self.showAlert(title: "Couldn't check for updates", message: error.localizedDescription) }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let urlString = json["html_url"] as? String,
                      let url = URL(string: urlString),
                      url.scheme == "https" else {
                    if visible { self.showAlert(title: "Couldn't check for updates", message: "Unexpected response from GitHub.") }
                    return
                }

                let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let notes = json["body"] as? String
                let downloadURL = (json["assets"] as? [[String: Any]])?
                    .first(where: { ($0["name"] as? String) == Self.assetName })
                    .flatMap { $0["browser_download_url"] as? String }
                    .flatMap { URL(string: $0) }
                    .flatMap { Self.isTrustedDownloadURL($0) ? $0 : nil }

                if AppInfo.isNewer(remote: remote, current: AppInfo.version) {
                    let update = AvailableUpdate(version: remote, url: url, downloadURL: downloadURL, notes: notes)
                    self.available = update
                    self.postNotification(update)
                    if visible {
                        // Manual "Check for Updates" click: surface a modal alert
                        // so the user gets the same feedback they get when already
                        // up-to-date, with buttons to install or open the release.
                        self.showUpdateAlert(update)
                    }
                } else {
                    self.available = nil
                    if visible {
                        self.showAlert(
                            title: "You're up to date",
                            message: "WhatBattery \(AppInfo.version) is the latest version."
                        )
                    }
                }
            }
        }.resume()
    }

    private func postNotification(_ update: AvailableUpdate) {
        // A bare binary (CLI / `swift run`) has no bundle identity, so
        // UNUserNotificationCenter can't be used; the banner still covers it.
        guard Bundle.main.bundleIdentifier != nil else { return }
        // Default on: an absent key reads as true, matching the Settings toggle's
        // @AppStorage default. Only an explicit `false` suppresses the notice.
        let wantsNotice = (UserDefaults.standard.object(forKey: Self.notifyKey) as? Bool) ?? true
        guard wantsNotice else { return }
        // Stamp only once we actually post, not when the version is first seen, so
        // toggling the setting back on after an update was detected still notifies.
        guard notifiedVersion != update.version else { return }
        notifiedVersion = update.version

        // Request quietly: a granted prompt or a no-op if already decided. Posting
        // before the grant resolves would drop the request, so post inside. The
        // closure runs off the main thread, so capture only Sendable values (the
        // version strings) and reach the center fresh inside rather than capturing
        // the non-Sendable `UNUserNotificationCenter`.
        let newVersion = update.version
        let currentVersion = AppInfo.version
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "WhatBattery \(newVersion) available"
            content.body = "You're on \(currentVersion). Open WhatBattery to update."
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "update-\(newVersion)", content: content, trigger: nil)
            )
        }
    }

    private func showAlert(title: String, message: String) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }

        // An accessory (LSUIElement) app can't reliably bring a modal alert to the
        // front. Briefly promote to a regular app so the alert takes focus, then
        // restore the accessory policy after dismissal.
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.window.level = .floating
        alert.runModal()

        NSApp.setActivationPolicy(originalPolicy)
    }

    private func showUpdateAlert(_ update: AvailableUpdate) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }

        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "WhatBattery \(update.version) is available"
        alert.informativeText = "You're on \(AppInfo.version). Install now, or open the release page to read the notes."
        alert.window.level = .floating
        let hasDownload = update.downloadURL != nil
        if hasDownload {
            alert.addButton(withTitle: "Update")
        }
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()

        NSApp.setActivationPolicy(originalPolicy)

        if hasDownload && response == .alertFirstButtonReturn {
            Installer.shared.install(update)
        } else if response == (hasDownload ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
            NSWorkspace.shared.open(update.url)
        }
    }

    /// Only accept download URLs from GitHub's release asset CDN.
    nonisolated static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https",
              let host = url.host else { return false }
        let trusted = ["objects.githubusercontent.com", "github.com", "releases.githubusercontent.com"]
        return trusted.contains(host)
    }
}
