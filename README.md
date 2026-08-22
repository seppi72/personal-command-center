# Personal Command Center

A self-hosted Vapor backend for a single-user system that aggregates the owner's
tasks, projects, calendar, and more. See `CONTEXT.md` for domain vocabulary and
`docs/adr/` for architecture decisions.

## Local setup

Requires Swift 6.0+ (matching `Package.swift`'s `swift-tools-version`) and a local PostgreSQL server.

1. Install and start Postgres (e.g. `brew install postgresql@16 && brew services start postgresql@16`).
2. Create the dev and test roles/databases:
   ```sh
   createuser pcc --pwprompt   # set password to match DATABASE_PASSWORD below, or edit pg_hba.conf for trust auth
   createdb -O pcc pcc_dev
   createdb -O pcc pcc_test
   ```
3. Set `AUTH_TOKENS` to a comma-separated list of bearer tokens (one per device is fine):
   ```sh
   export AUTH_TOKENS="mac-token,ios-token"
   ```
4. Run the app: `swift run App serve`
5. Run the tests: `swift test` (connects to `pcc_test`; override `DATABASE_*` env vars if your local setup differs from the defaults in `Sources/App/configure.swift`).

### Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `DATABASE_HOST` | `localhost` | Postgres host |
| `DATABASE_PORT` | `5432` | Postgres port |
| `DATABASE_USERNAME` | `pcc` | Postgres role |
| `DATABASE_PASSWORD` | `pcc_password` | Postgres role password |
| `DATABASE_NAME` | `pcc_dev` (`pcc_test` when `swift test` runs) | Database name |
| `AUTH_TOKENS` | _(none — all requests rejected)_ | Comma-separated bearer tokens accepted by every route |

## API

All routes require `Authorization: Bearer <token>` and are versioned under `/v1`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/health` | Liveness check (see `docs/adr/0001-self-hosted-backend-over-cloudkit.md`) |
| `GET` | `/v1/projects` | List all Projects |
| `POST` | `/v1/projects` | Create a Project (`{ "name": "..." }`) |
| `PUT` | `/v1/projects/:projectID` | Rename a Project (`{ "name": "..." }`) |
| `DELETE` | `/v1/projects/:projectID` | Delete a Project |
| `GET` | `/v1/tasks` | List all Tasks; add `?projectID=` to scope to one Project |
| `POST` | `/v1/tasks` | Create a Task, Project-less (`{ "title": "...", "notes": "..."? }`) |
| `PUT` | `/v1/tasks/:taskID` | Edit a Task's title/notes (`{ "title": "...", "notes": "..."? }`) |
| `DELETE` | `/v1/tasks/:taskID` | Delete a Task |
| `PUT` | `/v1/tasks/:taskID/complete` | Mark a Task complete |
| `PUT` | `/v1/tasks/:taskID/incomplete` | Mark a Task incomplete |
| `PUT` | `/v1/tasks/:taskID/project` | Assign/move/remove a Task's Project (`{ "projectID": "..."? }`, omit or `null` to remove) |

Deleting a Project doesn't delete its Tasks — they become Project-less.

## Client (Mac/iOS)

`Sources/PCCUI` is a shared SwiftUI library for the Projects screen
(`ProjectsView` + `ProjectsViewModel` + `URLSessionProjectsAPIClient`) and the
Tasks screen (`TasksView` + `TasksViewModel` + `URLSessionTasksAPIClient`),
built as a plain SPM target with no Vapor/Fluent dependency. It isn't wrapped
in an Xcode app target yet — no Xcode is set up in this environment. To use
it:

1. Create the Mac and/or iOS App targets in Xcode (`File > New > Project`).
2. Add this repository as a local Swift package dependency and link `PCCUI`.
3. From each app's entry point, construct a `URLSessionProjectsAPIClient` and
   `URLSessionTasksAPIClient` with the backend's base URL and the device's
   bearer token. Wrap the former in a `ProjectsViewModel` to show
   `ProjectsView(viewModel:)`; wrap both in a `TasksViewModel` (pass
   `scopedProjectID` to scope the screen to one Project, or omit it to list
   every Task) to show `TasksView(viewModel:)`.

The backend's `PCCTask` model and the client's `PCCTask` struct are named
`PCCTask` in Swift, not `Task` — that would shadow `_Concurrency.Task`
throughout their targets. The domain term "Task" is what appears in the API
paths/JSON and the UI text.

It has been verified with `swift build --target PCCUI` (type-checks and links)
but not run in a simulator or on-device.
