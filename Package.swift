// swift-tools-version: 5.9
import PackageDescription

// A library target that `import SwiftUI` makes the compiler autolink SwiftUICore
// directly. The macOS 26 SDK restricts SwiftUICore to allowed clients, which a
// SwiftPM executable is not, so the link fails. Suppress the direct SwiftUICore
// autolink and link SwiftUI explicitly instead (SwiftUI re-exports SwiftUICore).
let swiftUICoreAutolinkFix: SwiftSetting = .unsafeFlags([
    "-Xfrontend", "-disable-autolink-framework", "-Xfrontend", "SwiftUICore",
])

// Public (open-source) package manifest. Identical to the private one except the
// Pro module `WhatBatteryPlugins` is a no-op stub (just `bootstrapPlugins`), so it
// depends only on WhatBatteryAppKit and there is no plugins test target.
let package = Package(
    name: "WhatBattery",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatBattery", targets: ["WhatBattery"]),
        .executable(name: "whatbattery-cli", targets: ["WhatBatteryCLI"]),
        .library(name: "WhatBatteryCore", targets: ["WhatBatteryCore"]),
        .library(name: "WhatBatteryDarwinBackend", targets: ["WhatBatteryDarwinBackend"]),
        .library(name: "WhatBatteryAppKit", targets: ["WhatBatteryAppKit"]),
    ],
    targets: [
        .target(name: "WhatBatteryCore"),

        .target(
            name: "WhatBatteryDarwinBackend",
            dependencies: ["WhatBatteryCore"]
        ),

        .target(
            name: "WhatBatteryAppKit",
            dependencies: ["WhatBatteryCore"],
            swiftSettings: [swiftUICoreAutolinkFix]
        ),

        // No-op Pro stub (the public mirror has no Pro implementations).
        .target(
            name: "WhatBatteryPlugins",
            dependencies: ["WhatBatteryAppKit"]
        ),

        .executableTarget(
            name: "WhatBattery",
            dependencies: ["WhatBatteryCore", "WhatBatteryDarwinBackend", "WhatBatteryAppKit", "WhatBatteryPlugins"],
            swiftSettings: [swiftUICoreAutolinkFix],
            linkerSettings: [.linkedFramework("SwiftUI")]
        ),

        .executableTarget(
            name: "WhatBatteryCLI",
            dependencies: ["WhatBatteryCore", "WhatBatteryDarwinBackend", "WhatBatteryAppKit", "WhatBatteryPlugins"],
            linkerSettings: [.linkedFramework("SwiftUI")]
        ),

        .testTarget(
            name: "WhatBatteryCoreTests",
            dependencies: ["WhatBatteryCore"]
        ),
        .testTarget(
            name: "WhatBatteryDarwinTests",
            dependencies: ["WhatBatteryCore", "WhatBatteryDarwinBackend"]
        ),
    ]
)
