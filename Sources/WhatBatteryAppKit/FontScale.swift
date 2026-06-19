import SwiftUI

/// User-adjustable font scale for every panel. Stored as a multiplier in
/// `UserDefaults` under `"fontScale"` (default `1.0`), driven by a slider in
/// Settings, and pushed down the view tree as an environment value. Views opt in
/// by using `.scaledFont(...)` instead of `.font(...)`, which multiplies a base
/// point size by this scale. Lives in AppKit (not the app target) so the Pro
/// plugin views in `WhatBatteryPlugins` can read it too, same as
/// `IDeviceTabActiveKey`.

public struct FontScaleKey: EnvironmentKey {
    public static let defaultValue: Double = 1.0
}

public extension EnvironmentValues {
    var fontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

public enum FontScale {
    /// UserDefaults key the Settings slider binds to and every root view reads.
    public static let key = "fontScale"
    /// Slider range: 80% to 140%, matching WhatCable.
    public static let range: ClosedRange<Double> = 0.8...1.4
    /// Slider step.
    public static let step: Double = 0.1
    public static let defaultValue: Double = 1.0

    /// Clamp a stored/raw value into range, treating a missing key (`0`) as the
    /// default. `UserDefaults.double(forKey:)` returns `0` when the key is absent.
    public static func clamp(_ raw: Double) -> Double {
        let value = raw > 0 ? raw : defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Applies a `Font.system` font whose point size is `baseSize * fontScale`. Use
/// either a semantic text style (mapped to a base point size) or an explicit
/// size. Mirrors the live environment value, so every `.scaledFont` view tracks
/// the slider with no extra wiring.
public struct ScaledFontModifier: ViewModifier {
    @Environment(\.fontScale) private var scale
    let size: Double
    let design: Font.Design?
    let weight: Font.Weight?
    let monospacedDigit: Bool

    public init(size: Double, design: Font.Design? = nil, weight: Font.Weight? = nil, monospacedDigit: Bool = false) {
        self.size = size
        self.design = design
        self.weight = weight
        self.monospacedDigit = monospacedDigit
    }

    public func body(content: Content) -> some View {
        let scaled = size * scale
        var font: Font = design != nil
            ? .system(size: scaled, design: design!)
            : .system(size: scaled)
        if let weight { font = font.weight(weight) }
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }

    /// The default weight macOS applies to a semantic text style. Only `.headline`
    /// is non-regular (semibold); preserving it keeps section headers from going
    /// thin when `.font(.headline)` becomes `.scaledFont(.headline)`.
    public static func defaultWeight(for style: Font.TextStyle) -> Font.Weight? {
        style == .headline ? .semibold : nil
    }

    /// Base macOS point sizes for each semantic text style (matching WhatCable).
    public static func baseSize(for style: Font.TextStyle) -> Double {
        switch style {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .body:        return 13
        case .callout:     return 12
        case .subheadline: return 11
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 10
        @unknown default:  return 13
        }
    }
}

public extension View {
    /// Scaled equivalent of `.font(.<style>)`. The semantic style is mapped to a
    /// base point size, then multiplied by the user's font scale.
    func scaledFont(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil, monospacedDigit: Bool = false) -> some View {
        // Fall back to the style's native weight (semibold for headline) so a bare
        // .scaledFont(.headline) matches what .font(.headline) rendered.
        let effectiveWeight = weight ?? ScaledFontModifier.defaultWeight(for: style)
        return modifier(ScaledFontModifier(size: ScaledFontModifier.baseSize(for: style), design: design, weight: effectiveWeight, monospacedDigit: monospacedDigit))
    }

    /// Scaled equivalent of `.font(.system(size:...))` for fixed-size fonts (the
    /// big hero health numbers, icon buttons). The given size is multiplied by
    /// the user's font scale.
    func scaledFont(size: Double, weight: Font.Weight? = nil, design: Font.Design? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFontModifier(size: size, design: design, weight: weight, monospacedDigit: monospacedDigit))
    }
}
