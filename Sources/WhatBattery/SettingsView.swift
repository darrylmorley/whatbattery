import SwiftUI
import WhatBatteryCore
import WhatBatteryAppKit

/// App settings plus any plugin-contributed sections (the Pro licence section,
/// notifications later). Grows over time (history retention, menu bar badge).
struct SettingsView: View {
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    @AppStorage(FontScale.key) private var fontScale = FontScale.defaultValue
    /// The slider drags this local value and commits it to `fontScale` once, on
    /// release. Binding the slider straight to storage resized every panel
    /// (including the popover frame around this very form) on each drag tick,
    /// which flashed the popover and dragged it around under the menu bar.
    @State private var draggedScale: Double?
    @AppStorage(UpdateChecker.notifyKey) private var notifyOnUpdates = true
    @AppStorage(MenuBarBadge.key) private var menuBarBadge = MenuBarBadge.charge.rawValue
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    /// When embedded in the menu bar popover, drop the fixed window frame and let
    /// the content size to the popover.
    var embedded = false
    /// Height to give the embedded form, so it matches the popover (which is
    /// sized by the accessory list) and scrolls internally rather than clipping.
    var embeddedHeight: CGFloat = 340

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if let message = launchAtLoginNote {
                    Text(message)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Menu bar shows", selection: $menuBarBadge) {
                    ForEach(MenuBarBadge.allCases) { badge in
                        Text(badge.label).tag(badge.rawValue)
                    }
                }
            }

            Picker("Temperature", selection: $temperatureUnit) {
                Text("Celsius (C)").tag("C")
                Text("Fahrenheit (F)").tag("F")
            }
            .pickerStyle(.inline)

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text(verbatim: "\(Int(((draggedScale ?? fontScale) * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { draggedScale ?? fontScale },
                                set: { draggedScale = $0 }
                            ),
                            in: FontScale.range,
                            step: FontScale.step
                        ) { editing in
                            guard !editing, let dragged = draggedScale else { return }
                            fontScale = dragged
                            draggedScale = nil
                        }
                        // Keyboard and accessibility adjustments don't reliably
                        // report an editing end, so commit those after a beat of
                        // inactivity too. A mouse drag paused this long commits
                        // mid-drag, which is one resize, not a flicker.
                        .task(id: draggedScale) {
                            guard draggedScale != nil else { return }
                            // A new drag tick cancels this task; try? swallows
                            // the CancellationError, so check explicitly or the
                            // commit below would run on every tick.
                            try? await Task.sleep(for: .milliseconds(800))
                            guard !Task.isCancelled, let dragged = draggedScale else { return }
                            fontScale = dragged
                            draggedScale = nil
                        }
                        // Leaving the pane (the popover's Back button) tears
                        // this view down and cancels the fallback task, which
                        // silently dropped a keyboard adjustment made in the
                        // last 800ms. Flush it instead.
                        .onDisappear {
                            guard let dragged = draggedScale else { return }
                            fontScale = dragged
                            draggedScale = nil
                        }
                        // Another Settings instance (popover pane vs standalone
                        // window) committing while this one holds a draft wins:
                        // drop the draft rather than overwrite the newer value
                        // when the fallback fires. Our own commits clear the
                        // draft before this runs, so they pass through.
                        .onChange(of: fontScale) {
                            draggedScale = nil
                        }
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Software Update") {
                Toggle("Notify me about new versions", isOn: $notifyOnUpdates)
                HStack {
                    Button(updates.isChecking ? "Checking…" : "Check Now") {
                        updates.check(silent: false)
                    }
                    .disabled(updates.isChecking)
                    Spacer()
                    Text(updateStatusText)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(PluginRegistry.shared.settingsSections.enumerated()), id: \.offset) { _, build in
                build()
            }
        }
        .formStyle(.grouped)
        .environment(\.fontScale, FontScale.clamp(fontScale))
        // Embedded in the popover: a bounded height matching the popover, scrolling
        // internally. As a standalone window: fill a resizable window (with sane
        // minimums) so every section has room and the form scrolls if shrunk.
        .modifier(SettingsFrame(embedded: embedded, embeddedHeight: embeddedHeight))
        // The login item can be changed in System Settings while the app runs,
        // so re-read it whenever this form appears rather than trusting the
        // value cached at launch.
        .onAppear { launchAtLogin.refresh() }
    }

    /// The caption under the launch-at-login toggle: an explanation when the
    /// system is holding it off, the failure when one happened, and a nudge
    /// about why it matters otherwise. Nil once it is simply on.
    private var launchAtLoginNote: String? {
        if launchAtLogin.requiresApproval {
            return "Turned off in System Settings. Allow WhatBattery under General > Login Items to switch it back on."
        }
        if let error = launchAtLogin.lastError {
            return "Couldn't change this: \(error)"
        }
        if !launchAtLogin.isEnabled {
            return "Battery history is only recorded while WhatBattery is running."
        }
        return nil
    }

    /// The right-hand status next to "Check Now": a found update wins, otherwise
    /// the current version (the everyday "you're up to date" reassurance).
    private var updateStatusText: String {
        if let update = updates.available {
            return "Update available: v\(update.version)"
        }
        return "WhatBattery v\(AppInfo.version)"
    }
}

/// Sizes the settings form: a fixed height when embedded in the popover, or a
/// flexible fill with minimums when it's its own resizable window.
private struct SettingsFrame: ViewModifier {
    let embedded: Bool
    let embeddedHeight: CGFloat

    func body(content: Content) -> some View {
        if embedded {
            content.frame(height: embeddedHeight)
        } else {
            content.frame(
                minWidth: 400, idealWidth: 420, maxWidth: .infinity,
                minHeight: 420, idealHeight: 560, maxHeight: .infinity
            )
        }
    }
}
