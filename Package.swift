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
        // No view-level tests here: the v1 spec (#1) defers those until
        // there's a stable API to build against and calls for manual
        // verification instead. `PCCUITests` (below) is narrower than that
        // deferral — it covers `PCCHTTPTransport` only, a pure-logic module
        // with no view involved (ticket #54).
        .target(
            name: "PCCUI"
        ),
        .testTarget(
            name: "PCCUITests",
            dependencies: [
                .target(name: "PCCUI"),
            ]
        ),
        // Dev-only Mac preview app: a plain SPM executable (not an Xcode
        // app target) that composes every `PCCUI` screen into one window,
        // so the client can be viewed and iterated on with just `swift run`
        // — no Xcode required, since SwiftUI's `App` protocol runs fine as
        // a bare executable against the Command Line Tools' macOS SDK. Not
        // a substitute for the real Mac/iOS app targets described in the
        // README's "Consumers (Mac/iOS)" section (no app icon, no iOS
        // build — this can't run in the Simulator) — just a fast local
        // loop for seeing `PCCUI` changes without installing Xcode.
        .executableTarget(
            name: "PCCDesktop",
            dependencies: ["PCCUI"]
        ),
    ]
)
