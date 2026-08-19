// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sesame",
    platforms: [.macOS(.v14)], // Sonoma and up — runs on 14, 15, 26, 27
    dependencies: [
        // Prebuilt Google WebRTC (audio calls). Binary xcframework, loaded only when calling.
        .package(url: "https://github.com/stasel/WebRTC.git", "120.0.0"..<"200.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Sesame",
            dependencies: [.product(name: "WebRTC", package: "WebRTC")],
            path: "Sources/Sesame",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
