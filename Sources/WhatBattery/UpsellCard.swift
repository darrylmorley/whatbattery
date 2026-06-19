import SwiftUI
import WhatBatteryAppKit

/// The locked-feature upsell shown in place of a Pro section in the free build.
/// One parameterised card for every gate (history, accessories, iDevice, etc.)
/// so they stay visually identical and a copy tweak lands once.
struct UpsellCard: View {
    let title: String
    let systemImage: String
    let message: String

    private static let storeURL = URL(string: "https://www.whatbattery.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).scaledFont(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            Link("Get WhatBattery Pro", destination: Self.storeURL)
                .scaledFont(.callout)
            Text("Already have a key? Add it in Settings.")
                .scaledFont(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
