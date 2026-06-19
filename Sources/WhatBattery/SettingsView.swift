import SwiftUI
import WhatBatteryAppKit

/// App settings plus any plugin-contributed sections (the Pro licence section,
/// notifications later). Grows over time (history retention, menu bar badge,
/// launch at login).
struct SettingsView: View {
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    @AppStorage(FontScale.key) private var fontScale = FontScale.defaultValue
    /// When embedded in the menu bar popover, drop the fixed window frame and let
    /// the content size to the popover.
    var embedded = false
    /// Height to give the embedded form, so it matches the popover (which is
    /// sized by the accessory list) and scrolls internally rather than clipping.
    var embeddedHeight: CGFloat = 340

    var body: some View {
        Form {
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
                        Text(verbatim: "\(Int((fontScale * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $fontScale, in: FontScale.range, step: FontScale.step)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
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
