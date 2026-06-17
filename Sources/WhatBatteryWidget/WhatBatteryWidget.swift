import SwiftUI
import WidgetKit
import WhatBatteryCore

@main
struct WhatBatteryWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
    }
}

struct BatteryWidget: Widget {
    let kind = "app.whatbattery.whatbattery.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryTimelineProvider()) { entry in
            BatteryWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Battery health and charge at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
