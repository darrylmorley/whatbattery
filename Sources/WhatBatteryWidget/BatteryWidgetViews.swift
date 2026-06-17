import SwiftUI
import WidgetKit
import WhatBatteryCore

struct BatteryWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall:
                BatterySmallView(snapshot: snapshot)
            default:
                BatteryMediumView(snapshot: snapshot)
            }
        } else {
            BatteryEmptyView()
        }
    }
}

// MARK: - Small: health hero + charge caption

struct BatterySmallView: View {
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: snapshot.batteryIcon)
                    .font(.title3)
                    .foregroundStyle(snapshot.chargeColor)
                Spacer()
                if let watts = snapshot.adapter?.watts {
                    Text("\(watts)W")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(BatteryFormatter.healthPercent(snapshot.healthPercent))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(snapshot.healthColor)
            Text("Battery health")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.chargeCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium: health + live state side by side

struct BatteryMediumView: View {
    let snapshot: BatterySnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(BatteryFormatter.healthPercent(snapshot.healthPercent))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.healthColor)
                Text("Battery health")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if snapshot.fullChargeCapacitymAh > 0 {
                    Text("\(BatteryFormatter.milliampHours(snapshot.fullChargeCapacitymAh)) of \(BatteryFormatter.milliampHours(snapshot.designCapacitymAh))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Text("\(snapshot.cycleCount) cycles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.batteryIcon)
                        .foregroundStyle(snapshot.chargeColor)
                    Text("\(snapshot.currentChargePercent)%")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                Text(snapshot.chargeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(BatteryFormatter.temperature(snapshot.temperatureCelsius))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let label = snapshot.adapter?.label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Empty state

struct BatteryEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No battery data")
                .font(.headline)
            Text("Open WhatBattery to start.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Presentation helpers

private extension BatterySnapshot {
    var batteryIcon: String {
        switch chargingState {
        case .charging, .full:
            return "battery.100.bolt"
        case .acNoCharge, .discharging:
            switch currentChargePercent {
            case ..<13: return "battery.0"
            case ..<38: return "battery.25"
            case ..<63: return "battery.50"
            case ..<88: return "battery.75"
            default: return "battery.100"
            }
        }
    }

    var chargeColor: Color {
        switch chargingState {
        case .full: return .green
        case .charging: return .yellow
        case .acNoCharge, .discharging: return .secondary
        }
    }

    var healthColor: Color {
        switch healthPercent ?? 100 {
        case ..<60: return .red
        case ..<80: return .orange
        default: return .green
        }
    }

    var chargeCaption: String {
        switch chargingState {
        case .charging:
            if let eta = BatteryFormatter.duration(minutes: timeToFullMinutes) {
                return "\(currentChargePercent)%, \(eta) to full"
            }
            return "\(currentChargePercent)%, charging"
        case .discharging:
            if let eta = BatteryFormatter.duration(minutes: timeToEmptyMinutes) {
                return "\(currentChargePercent)%, \(eta) left"
            }
            return "\(currentChargePercent)%, on battery"
        case .full:
            return "Fully charged"
        case .acNoCharge:
            return "\(currentChargePercent)%, on AC"
        }
    }
}
