// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ADSB Radar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RadarCore", targets: ["RadarCore"]),
        .executable(name: "ADSB Radar", targets: ["ADSBRadar"])
    ],
    targets: [
        .target(name: "RadarCore"),
        .executableTarget(name: "ADSBRadar", dependencies: ["RadarCore"], resources: [.process("Resources")]),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"]),
        .testTarget(name: "ADSBRadarTests", dependencies: ["ADSBRadar", "RadarCore"])
    ]
)
