// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SayItFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SayItFlow", targets: ["SayItFlow"])
    ],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", exact: "3.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.4.0")
    ],
    targets: [
        .target(
            name: "AudioTapCore",
            path: "SayItFlow/Audio",
            exclude: ["AudioInput.swift"],
            sources: ["AudioTapHelper.m"],
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "SayItFlow",
            dependencies: [
                "AudioTapCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Voz", package: "desert-ant-core")
            ],
            path: "SayItFlow",
            exclude: [
                "Audio/AudioTapHelper.h",
                "Audio/AudioTapHelper.m",
                "Info.plist",
                "SayItFlow.entitlements",
                "SayItFlow-Bridging-Header.h"
            ]
        )
    ]
)
