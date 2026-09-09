// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snipzy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Snipzy", targets: ["Snipzy"])
    ],
    targets: [
        .executableTarget(
            name: "Snipzy",
            path: "Sources/Snipzy"
        ),
        .testTarget(
            name: "SnipzyTests",
            dependencies: ["Snipzy"],
            path: "Tests/SnipzyTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
