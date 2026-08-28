// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "XanoRealtime",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "XanoRealtime",
            targets: ["XanoRealtime"]
        )
    ],
    targets: [
        .target(
            name: "XanoRealtime",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "XanoRealtimeTests",
            dependencies: ["XanoRealtime"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .testTarget(
            name: "XanoRealtimeAPIValidator",
            dependencies: ["XanoRealtime"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        )
    ]
)
