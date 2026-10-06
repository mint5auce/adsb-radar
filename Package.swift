// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ADSB Radar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RadarCore", targets: ["RadarCore"]),
        .executable(name: "ADSB Radar", targets: ["ADSBRadar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "RadarCore"),
        .executableTarget(name: "MapDataTool", dependencies: ["RadarCore"]),
        .executableTarget(name: "ADSBRadar", dependencies: ["RadarCore", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.process("Resources")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"], resources: [.process("Fixtures")]),
        .testTarget(name: "ADSBRadarTests", dependencies: ["ADSBRadar", "RadarCore"])
    ]
)
