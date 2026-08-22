import Fluent
import FluentPostgresDriver
import PostgresKit
import Vapor

public func configure(_ app: Application) async throws {
    let defaultDatabaseName: String
    if app.environment == .testing {
        defaultDatabaseName = "pcc_test"
    } else {
        defaultDatabaseName = "pcc_dev"
    }

    let hostname: String = Environment.get("DATABASE_HOST") ?? "localhost"
    let username: String = Environment.get("DATABASE_USERNAME") ?? "pcc"
    let password: String = Environment.get("DATABASE_PASSWORD") ?? "pcc_password"
    let databaseName: String = Environment.get("DATABASE_NAME") ?? defaultDatabaseName

    var port = 5432
    if let configuredPort = Environment.get("DATABASE_PORT"), let parsedPort = Int(configuredPort) {
        port = parsedPort
    }

    let postgresConfiguration = SQLPostgresConfiguration(
        hostname: hostname,
        port: port,
        username: username,
        password: password,
        database: databaseName,
        tls: .disable
    )
    app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)

    app.migrations.add(CreateHealthPing())
    app.migrations.add(CreateProject())
    app.migrations.add(CreatePCCTask())
    app.migrations.add(AddDeadlineToProject())
    app.migrations.add(AddDeadlineToPCCTask())
    try await app.autoMigrate()

    let validTokens = Set(
        (Environment.get("AUTH_TOKENS") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    )
    if validTokens.isEmpty {
        app.logger.warning("No AUTH_TOKENS configured — every request will be rejected with 401.")
    }
    app.middleware.use(BearerTokenAuthMiddleware(validTokens: validTokens))

    try routes(app)
}
