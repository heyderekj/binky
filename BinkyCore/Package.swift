// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BinkyCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "BinkyCoreShared", targets: ["BinkyCoreShared"]),
        .library(name: "BinkyCoreSort", targets: ["BinkyCoreSort"]),
        .library(name: "BinkyCLILib", targets: ["BinkyCLILib"]),
        .executable(name: "binky", targets: ["BinkyCLI"]),
    ],
    targets: [
        .target(
            name: "BinkyCoreShared",
            dependencies: [],
            path: "Sources/BinkyCoreShared"
        ),
        .target(
            name: "BinkyCoreSort",
            dependencies: ["BinkyCoreShared"],
            path: "Sources/BinkyCoreSort"
        ),
        .target(
            name: "BinkyCLILib",
            dependencies: ["BinkyCoreShared", "BinkyCoreSort"],
            path: "Sources/BinkyCLILib"
        ),
        .executableTarget(
            name: "BinkyCLI",
            dependencies: ["BinkyCLILib"],
            path: "Sources/BinkyCLI"
        ),
        // Test target — runs via `swift test` from the BinkyCore directory.
        // CI invokes this in a separate step from the Xcode app's test bundle so
        // BinkyCore-level regressions surface even when LaunchServices flakes
        // out the Xcode test runner. See `.github/workflows/ci.yml`.
        .testTarget(
            name: "BinkyCoreSharedTests",
            dependencies: ["BinkyCoreShared"],
            path: "Tests/BinkyCoreSharedTests"
        ),
        .testTarget(
            name: "BinkyCoreSortTests",
            dependencies: ["BinkyCoreSort", "BinkyCoreShared"],
            path: "Tests/BinkyCoreSortTests"
        ),
    ]
)
