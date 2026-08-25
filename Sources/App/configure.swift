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
    app.migrations.add(CreatePCCClient())
    app.migrations.add(AddClientToProject())
    app.migrations.add(CreatePersonalCommitment())
    app.migrations.add(CreateAutomationLog())
    app.migrations.add(CreateMirroredCalendarEvent())
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

    // Only install the real CalDAV client if nothing has been injected
    // already — tests set `app.calDAVClient` to a `FakeCalDAVClient` before
    // calling `configure(_:)` (see `Application+CalDAVClient.swift`).
    if !app.hasCalDAVClient {
        let calendarURLString = Environment.get("CALDAV_CALENDAR_URL") ?? "https://caldav.icloud.com/unconfigured/"
        guard let calendarURL = URL(string: calendarURLString) else {
            fatalError("CALDAV_CALENDAR_URL is not a valid URL: \(calendarURLString)")
        }
        let caldavUsername = Environment.get("CALDAV_USERNAME") ?? ""
        let caldavPassword = Environment.get("CALDAV_APP_SPECIFIC_PASSWORD") ?? ""
        if caldavUsername.isEmpty || caldavPassword.isEmpty {
            app.logger.warning(
                "No CALDAV_USERNAME/CALDAV_APP_SPECIFIC_PASSWORD configured — Personal Commitment CalDAV pushes will fail and be logged to AutomationLog rather than silently no-op."
            )
        }
        app.calDAVClient = ICloudCalDAVClient(
            calendarURL: calendarURL,
            username: caldavUsername,
            appSpecificPassword: caldavPassword
        )
    }

    // The recurring background sync job (ticket #7) doesn't run during
    // tests — see `startCalendarSyncSchedule`'s doc comment for why.
    if app.environment != .testing {
        let intervalSeconds = Environment.get("CALENDAR_SYNC_INTERVAL_SECONDS").flatMap(Int.init) ?? 300
        startCalendarSyncSchedule(app, interval: .seconds(intervalSeconds))
    }

    try routes(app)
}
