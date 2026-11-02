// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImmersiveWeather",
    platforms: [
        .visionOS(.v2),
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ImmersiveWeather", targets: ["ImmersiveWeather"]),
    ],
    targets: [
        // Structs shared between Swift and the Metal compute shaders.
        .target(name: "WaterShaderTypes"),
        .target(
            name: "ImmersiveWeather",
            dependencies: ["WaterShaderTypes"],
            resources: [.process("Shaders")]
        ),
        .testTarget(name: "ImmersiveWeatherTests", dependencies: ["ImmersiveWeather"]),
    ]
)
