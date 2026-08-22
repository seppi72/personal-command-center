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
| `CALDAV_CALENDAR_URL` | `https://caldav.icloud.com/unconfigured/` | The target iCloud CalDAV calendar collection's own URL — see "CalDAV setup" below |
| `CALDAV_USERNAME` | _(none)_ | The iCloud Apple ID for the calendar above |
| `CALDAV_APP_SPECIFIC_PASSWORD` | _(none)_ | An [app-specific password](https://support.apple.com/en-us/102654) for that Apple ID — never a real account password |

### CalDAV setup

Personal Commitments (ticket #6) push to a specific iCloud calendar via CalDAV (`docs/adr/0002-caldav-over-eventkit-for-calendar-sync.md`). `ICloudCalDAVClient` targets one calendar collection URL directly — it does not perform the CalDAV principal/calendar-home discovery dance (`PROPFIND` against `https://caldav.icloud.com`) that resolves an Apple ID into that URL. Until `CALDAV_CALENDAR_URL`/`CALDAV_USERNAME`/`CALDAV_APP_SPECIFIC_PASSWORD` are set, every push fails (logged to `AutomationLog`, not silently dropped — see "Personal Commitments" below) rather than being skipped.

To find your calendar's collection URL: generate an app-specific password at [appleid.apple.com](https://appleid.apple.com), then issue a CalDAV `PROPFIND` against `https://caldav.icloud.com/` with that Apple ID/password (e.g. via a CalDAV-aware client, or `curl -u "<apple-id>:<app-specific-password>" -X PROPFIND ...` following the `calendar-home-set` property) to locate the calendar you want Commitments pushed to, of the form `https://pXX-caldav.icloud.com/<numeric-id>/calendars/<calendar-name>/`.

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
| `PUT` | `/v1/tasks/:taskID/deadline` | Attach/change/remove a Task's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `PUT` | `/v1/projects/:projectID/deadline` | Attach/change/remove a Project's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `GET` | `/v1/deadlines` | Every Task and Project together, ordered by Deadline proximity (undated items included, sorted last) |
| `GET` | `/v1/personal-commitments` | List all Personal Commitments |
| `POST` | `/v1/personal-commitments` | Create a Personal Commitment (`{ "title": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>", "recurrenceRule": "..."? }`) and push it to CalDAV |
| `PUT` | `/v1/personal-commitments/:commitmentID` | Edit a Personal Commitment (same body as create) and re-push it to CalDAV |
| `DELETE` | `/v1/personal-commitments/:commitmentID` | Delete a Personal Commitment and remove its CalDAV event |

Deleting a Project doesn't delete its Tasks — they become Project-less.

### Personal Commitments

A Personal Commitment (`CONTEXT.md`) is canonical — the Command Center owns it, not the external Calendar — so create/edit/delete always succeed locally regardless of whether the CalDAV push succeeds. Each push (or removal) is attempted synchronously in the same request, and its outcome is written to `AutomationLog` and reflected in the Commitment's `syncStatus` (`pending` → `synced` or `failed`) in the response, rather than failing the request. Retrying a failed push and pulling external events *in* are ticket #7's job; browsing `AutomationLog` itself is ticket #8's.

## Client (Mac/iOS)

`Sources/PCCUI` is a shared SwiftUI library for the Projects screen
(`ProjectsView` + `ProjectsViewModel` + `URLSessionProjectsAPIClient`), the
Tasks screen (`TasksView` + `TasksViewModel` + `URLSessionTasksAPIClient`),
the read-only Deadlines screen (`DeadlinesView` + `DeadlinesViewModel` +
`URLSessionDeadlinesAPIClient`), and the Personal Commitments screen
(`PersonalCommitmentsView` + `PersonalCommitmentsViewModel` +
`URLSessionPersonalCommitmentsAPIClient`), built as a plain SPM target with
no Vapor/Fluent dependency. It isn't wrapped in an Xcode app target yet — no
Xcode is set up in this environment. To use it:

1. Create the Mac and/or iOS App targets in Xcode (`File > New > Project`).
2. Add this repository as a local Swift package dependency and link `PCCUI`.
3. From each app's entry point, construct a `URLSessionProjectsAPIClient`,
   `URLSessionTasksAPIClient`, `URLSessionDeadlinesAPIClient`, and
   `URLSessionPersonalCommitmentsAPIClient` with the backend's base URL and
   the device's bearer token. Wrap each in its matching view model to show
   `ProjectsView(viewModel:)`, `TasksView(viewModel:)` (pass
   `scopedProjectID` to scope the screen to one Project, or omit it to list
   every Task), `DeadlinesView(viewModel:)`, and
   `PersonalCommitmentsView(viewModel:)`. A Task or Project's Deadline is
   set/cleared from its own create/edit form in `TasksView`/`ProjectsView` —
   the Deadlines screen is a read-only sorted view of both. Each
   Commitment's sync status (pushed to CalDAV, or failed — see "CalDAV
   setup" above) shows as a badge on its row in `PersonalCommitmentsView`.

The backend's `PCCTask` model and the client's `PCCTask` struct are named
`PCCTask` in Swift, not `Task` — that would shadow `_Concurrency.Task`
throughout their targets. The domain term "Task" is what appears in the API
paths/JSON and the UI text.

It has been verified with `swift build --target PCCUI` (type-checks and links)
but not run in a simulator or on-device.
