// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "personal-command-center",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.13.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
        // Shared SwiftUI client code for the Mac and iOS apps (ticket #3).
        // No Vapor/Fluent dependency — this is a plain client of the `App`
        // backend's HTTP API, not a server-side target. Not yet wrapped in
        // an Xcode app target; see README for how to drop it into one.
        // No tests here: the v1 spec (#1) defers SwiftUI view-level tests
        // until there's a stable API to build against and calls for manual
        // verification instead — the API itself is what's integration-tested.
        .target(
            name: "PCCUI"
        ),
    ]
)
