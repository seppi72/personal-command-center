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
| `CALENDAR_SYNC_INTERVAL_SECONDS` | `300` | How often the recurring background sync job (ticket #7) pulls external Calendar events and retries not-yet-synced Commitment pushes. Not read/used when `swift test` runs — see "Calendar sync" below |

### CalDAV setup

Personal Commitments (ticket #6) push to a specific iCloud calendar via CalDAV (`docs/adr/0002-caldav-over-eventkit-for-calendar-sync.md`). `ICloudCalDAVClient` targets one calendar collection URL directly — it does not perform the CalDAV principal/calendar-home discovery dance (`PROPFIND` against `https://caldav.icloud.com`) that resolves an Apple ID into that URL. Until `CALDAV_CALENDAR_URL`/`CALDAV_USERNAME`/`CALDAV_APP_SPECIFIC_PASSWORD` are set, every push fails (logged to `AutomationLog`, not silently dropped — see "Personal Commitments" below) rather than being skipped.

To find your calendar's collection URL: generate an app-specific password at [appleid.apple.com](https://appleid.apple.com), then issue a CalDAV `PROPFIND` against `https://caldav.icloud.com/` with that Apple ID/password (e.g. via a CalDAV-aware client, or `curl -u "<apple-id>:<app-specific-password>" -X PROPFIND ...` following the `calendar-home-set` property) to locate the calendar you want Commitments pushed to, of the form `https://pXX-caldav.icloud.com/<numeric-id>/calendars/<calendar-name>/`.

## API

All routes require `Authorization: Bearer <token>` and are versioned under `/v1`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/health` | Liveness check (see `docs/adr/0001-self-hosted-backend-over-cloudkit.md`) |
| `GET` | `/v1/projects` | List all Projects; add `?clientID=` to scope to one Client |
| `POST` | `/v1/projects` | Create a Project (`{ "name": "..." }`) |
| `PUT` | `/v1/projects/:projectID` | Rename a Project (`{ "name": "..." }`) |
| `DELETE` | `/v1/projects/:projectID` | Delete a Project |
| `PUT` | `/v1/projects/:projectID/client` | Assign/move/remove a Project's Client (`{ "clientID": "..."? }`, omit or `null` to remove) |
| `GET` | `/v1/clients` | List all Clients |
| `POST` | `/v1/clients` | Create a Client (`{ "name": "..." }`) |
| `PUT` | `/v1/clients/:clientID` | Rename a Client (`{ "name": "..." }`) |
| `DELETE` | `/v1/clients/:clientID` | Delete a Client |
| `GET` | `/v1/tasks` | List all Tasks; add `?projectID=` to scope to one Project and/or `?sprintID=` to scope to one Sprint |
| `POST` | `/v1/tasks` | Create a Task, Project-less (`{ "title": "...", "notes": "..."? }`) |
| `PUT` | `/v1/tasks/:taskID` | Edit a Task's title/notes (`{ "title": "...", "notes": "..."? }`) |
| `DELETE` | `/v1/tasks/:taskID` | Delete a Task |
| `PUT` | `/v1/tasks/:taskID/complete` | Mark a Task complete |
| `PUT` | `/v1/tasks/:taskID/incomplete` | Mark a Task incomplete |
| `PUT` | `/v1/tasks/:taskID/project` | Assign/move/remove a Task's Project (`{ "projectID": "..."? }`, omit or `null` to remove) — clears the Task's Sprint if it moves to a different Project |
| `PUT` | `/v1/tasks/:taskID/deadline` | Attach/change/remove a Task's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `PUT` | `/v1/tasks/:taskID/sprint` | Assign/move/remove a Task's Sprint (`{ "sprintID": "..."? }`, omit or `null` to remove) — rejects a Sprint that doesn't belong to the Task's current Project |
| `GET` | `/v1/sprints` | List a Project's Sprints — `?projectID=` is required |
| `POST` | `/v1/sprints` | Create a Sprint within a Project (`{ "projectID": "...", "name": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>" }`) |
| `PUT` | `/v1/sprints/:sprintID` | Edit a Sprint's name/dates (`{ "name": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>" }`) |
| `DELETE` | `/v1/sprints/:sprintID` | Delete a Sprint |
| `PUT` | `/v1/projects/:projectID/deadline` | Attach/change/remove a Project's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `GET` | `/v1/deadlines` | Every Task and Project together, ordered by Deadline proximity (undated items included, sorted last) |
| `GET` | `/v1/personal-commitments` | List all Personal Commitments |
| `POST` | `/v1/personal-commitments` | Create a Personal Commitment (`{ "title": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>", "recurrenceRule": "..."? }`) and push it to CalDAV |
| `PUT` | `/v1/personal-commitments/:commitmentID` | Edit a Personal Commitment (same body as create) and re-push it to CalDAV |
| `DELETE` | `/v1/personal-commitments/:commitmentID` | Delete a Personal Commitment and remove its CalDAV event |
| `GET` | `/v1/calendar-events` | List every mirrored external Calendar event (read-only — no create/update/delete; see "Calendar sync" below) |
| `GET` | `/v1/automation-logs` | Recent `AutomationLog` entries, most recent first, plus the most recent sync failure (if any) singled out (read-only; see "Automation Log" below) |

Deleting a Project doesn't delete its Tasks — they become Project-less. Deleting a Client doesn't delete its Projects — they become Client-less, the same orphaning shape.

### Clients (ticket #17)

A Client (`CONTEXT.md`) sits above Project, not beside it — created directly by the owner, since there's no external source of "you have a new client" to auto-detect one from. `ClientController` is a plain CRUD surface, same shape as `ProjectController`'s name-only create/edit. `ProjectController.setClient` (`PUT /v1/projects/:projectID/client`) assigns, moves, or removes a Project's Client — the same "one write handles all three ACs" shape `TaskController.assignProject` already has for a Task's Project.

Both the backend model and the client-side struct are named `PCCClient` in Swift, not `Client` — that would collide with Vapor's own `Client` protocol (`app.client`/`req.client`) server-side, the same problem `PCCTask` sidesteps for `_Concurrency.Task`. For the same reason, the backend's Client JSON response type is `PCCClientResponse`, not `ClientResponse` — Vapor already declares its own `ClientResponse` (the response type of `app.client`'s HTTP calls), so the unqualified name is ambiguous even though only one is ever in scope for a JSON body. The domain term "Client" is what shows up everywhere that matters — the `schema`, the JSON API, docs, and UI text.

### Sprints (ticket #18)

A Sprint (`CONTEXT.md`) is a time-boxed iteration within one Project that Tasks can be grouped into. A Project's use of Sprints is optional, but a Sprint itself is scoped to the Project it was created in for its lifetime — it doesn't move to a different Project, so `SprintController` never exposes a way to reassign a Sprint's Project (`UpdateSprintRequest` carries only `name`/`startDate`/`endDate`, not `projectID`). Because a Sprint has no meaning outside a Project, `GET /v1/sprints` requires `?projectID=` — unlike `GET /v1/clients` or `GET /v1/projects`, there's no "list all Sprints" story.

`Sprint.project` is a non-optional `@Parent`, not an `@OptionalParent` like `PCCTask.project` — a Sprint cannot exist without exactly one owning Project. That's why `CreateSprint`'s `project_id` foreign key uses `.cascade`, not `.setNull`: deleting a Project deletes its Sprints along with it, the opposite tradeoff from `AddClientToProject`'s `.setNull` (where the child, Project, *can* exist without the parent). A Task's relationship to its Sprint is the usual optional one, though — `AddSprintToPCCTask`'s `sprint_id` is nullable with `.setNull`, so deleting a Sprint makes its Tasks Sprint-less rather than deleting them, the same orphaning shape `CreatePCCTask`'s `project_id` already has for a deleted Project.

`TaskController.assignSprint` (`PUT /v1/tasks/:taskID/sprint`) rejects a Sprint that doesn't belong to the Task's *current* Project — checked by comparing `sprint.$project.id` against `task.$project.id`, which also correctly rejects any Sprint for a currently Project-less Task, since no Sprint's `project.id` can equal `nil`. `TaskController.assignProject` (`PUT /v1/tasks/:taskID/project`) clears the Task's Sprint whenever the incoming `projectID` differs from its current one (including moving to Project-less) — a Sprint that belonged to the old Project no longer applies once the Task moves. Moving a Task to the Project it's already in leaves its Sprint untouched.

### Personal Commitments

A Personal Commitment (`CONTEXT.md`) is canonical — the Command Center owns it, not the external Calendar — so create/edit/delete always succeed locally regardless of whether the CalDAV push succeeds. Each push (or removal) is attempted synchronously in the same request, and its outcome is written to `AutomationLog` and reflected in the Commitment's `syncStatus` (`pending` → `synced` or `failed`) in the response, rather than failing the request. The recurring sync job (below) is what retries a failed push later; browsing `AutomationLog` itself is ticket #8's.

### Calendar sync (ticket #7)

`CalendarSyncService.runScheduledSync` runs inside the Vapor process on a recurring interval (`CALENDAR_SYNC_INTERVAL_SECONDS`, default every 5 minutes), independent of whether the Mac or iOS app is open (spec #1, user story 23), and does two things each time:

1. **Pull**: fetches every event on the configured CalDAV calendar and upserts it (by external event id) into the read-only `MirroredCalendarEvent` cache, exposed at `GET /v1/calendar-events`. A repeated pull converges to whatever the external Calendar currently has rather than growing the cache forever.
2. **Push retry**: re-attempts the CalDAV push for every Personal Commitment not currently `synced` (i.e. `pending` or `failed`) — a safety net for a push that failed transiently, since `PersonalCommitmentController` already pushes synchronously on every create/edit and a Commitment stuck at `failed` would otherwise have no owner action to retry it.

A pull writes one `AutomationLog` entry (`actionType: "calendar.pull"`) per `MirroredCalendarEvent` it actually creates or changes — `subjectID` points at that row's own id, the same way a push's `subjectID` points at the Commitment it touched — and none for an event whose fields are unchanged since the last pull, so a quiet interval with nothing new doesn't flood the log; `lastSyncedAt` on every row (visible via `GET /v1/calendar-events`) is what confirms the pull itself is still running even when there's nothing to log. The one exception is a pull that fails before fetching any events at all, which has no affected row to log against and so logs once against a synthetic subject instead. A push retry writes one `personal_commitment.scheduled_sync` entry per Commitment it retries, the same way a controller-triggered push does. The job doesn't run when `swift test` runs (`app.environment == .testing`) — tests instead call `CalendarSyncService.pull()`/`pushPendingCommitments()`/`runScheduledSync()` directly against a `FakeCalDAVClient` and the real test database (`Tests/AppTests/CalendarSyncServiceTests.swift`), the same testing seam as `PersonalCommitmentTests`.

`ICloudCalDAVClient.fetchEvents()` (the pull's outbound call) issues a CalDAV `calendar-query` `REPORT` and hand-parses the multistatus XML response and each event's `.ics` body — same "hand-rolling event serialization/parsing" trade-off ADR-0002 accepted for the push side. Like `upsertEvent`/`deleteEvent`, it isn't itself covered by an automated test — only `CalendarSyncService`'s use of the `CalDAVClient` protocol is, via the fake.

### Automation Log (ticket #8)

`GET /v1/automation-logs` is the owner-facing read of `AutomationLog` (`CONTEXT.md`): every automated action's outcome, written by `CalendarSyncService`'s `push`/`remove`/`pull` today and whatever automation lands next. The response has two parts — `entries`, the 100 most recent log rows (most recent first), and `mostRecentFailure`, the single most recent entry with `outcome: "failure"` across the *entire* log, not just whichever of it happens to fall inside `entries`. Computing it separately is what keeps a failure from going unnoticed just because enough successes have piled up since to push it out of the recent list — the visible, singled-out failure state spec #1 asks for rather than one that silently scrolls out of view. `AutomationLogController` is read-only, same as `MirroredCalendarEventController` — no create/update/delete routes.

## Consumers (Mac/iOS)

`Sources/PCCUI` is a shared SwiftUI library for the Projects screen
(`ProjectsView` + `ProjectsViewModel` + `URLSessionProjectsAPIClient`), the
Tasks screen (`TasksView` + `TasksViewModel` + `URLSessionTasksAPIClient`),
the read-only Deadlines screen (`DeadlinesView` + `DeadlinesViewModel` +
`URLSessionDeadlinesAPIClient`), the Personal Commitments screen
(`PersonalCommitmentsView` + `PersonalCommitmentsViewModel` +
`URLSessionPersonalCommitmentsAPIClient`), the combined Calendar screen
(`CalendarView` + `CalendarViewModel` +
`URLSessionPersonalCommitmentsAPIClient` +
`URLSessionMirroredCalendarEventsAPIClient`, ticket #7), the Automation
Log screen (`AutomationLogView` + `AutomationLogViewModel` +
`URLSessionAutomationLogsAPIClient`, ticket #8), the Clients screen
(`ClientsView` + `ClientsViewModel` + `URLSessionClientsAPIClient`,
ticket #17), and a Sprints section within the Project detail flow
(`ProjectDetailView` + `SprintsViewModel` + `URLSessionSprintsAPIClient`,
ticket #18), built as a plain SPM target with no Vapor/Fluent dependency.
It isn't wrapped in an Xcode app target yet — no Xcode is set up in this
environment. To use it:

1. Create the Mac and/or iOS App targets in Xcode (`File > New > Project`).
2. Add this repository as a local Swift package dependency and link `PCCUI`.
3. From each app's entry point, construct a `URLSessionProjectsAPIClient`,
   `URLSessionTasksAPIClient`, `URLSessionDeadlinesAPIClient`,
   `URLSessionPersonalCommitmentsAPIClient`,
   `URLSessionMirroredCalendarEventsAPIClient`,
   `URLSessionAutomationLogsAPIClient`, `URLSessionClientsAPIClient`, and
   `URLSessionSprintsAPIClient` with the backend's base URL and the device's
   bearer token. Wrap each in its matching view model to show
   `ProjectsView(viewModel:)`, `TasksView(viewModel:)` (pass
   `scopedProjectID` to scope the screen to one Project, or omit it to list
   every Task), `DeadlinesView(viewModel:)`,
   `PersonalCommitmentsView(viewModel:)`, `CalendarView(viewModel:)`,
   `AutomationLogView(viewModel:)`, and `ClientsView(viewModel:)`. A Task
   or Project's Deadline is set/cleared from its own create/edit form in
   `TasksView`/`ProjectsView` — the Deadlines screen is a read-only sorted
   view of both. Each Commitment's sync status (pushed to CalDAV, or
   failed — see "CalDAV setup" above) shows as a badge on its row in both
   `PersonalCommitmentsView` and `CalendarView`. `ProjectsView` shows each
   row's Client name (via `ProjectsViewModel.clientName(for:)`) when the
   Project has one — assigning/moving/removing a Project's Client itself is
   API-only for now (`PUT /v1/projects/:projectID/client`); ticket #17's
   Mac/iOS scope is the indicator plus a standalone `ClientsView` for
   Client CRUD, not a Client picker inside `ProjectFormSheet`.
   `ProjectsViewModel` now also takes a `sprintsClient: SprintsAPIClient` in
   its `init`, used by its `makeSprintsViewModel(for:)` factory. Tapping a
   Project row navigates into `ProjectDetailView` (ticket #18) instead of
   opening the edit sheet directly — that sheet moved to
   `ProjectDetailView`'s own toolbar "Edit" button, with the same
   `ProjectFormSheet` wiring as before. `ProjectDetailView` shows the
   Project's name/due date read-only above a "Sprints" section: each
   Sprint's name and date range, with add/edit/delete via `SprintFormSheet`
   (name field plus start/end `DatePicker`s). A Sprint's own Project isn't
   editable from that sheet — it's set at creation and never reassigned.
   Assigning/moving/removing a *Task's* Sprint is API-only for now (`PUT
   /v1/tasks/:taskID/sprint`), the same "list plus API-only assignment"
   scope ticket #17 drew around Project-Client assignment.
4. `CalendarView` merges Personal Commitments and mirrored external Calendar
   events (populated by the backend's recurring sync job — see "Calendar
   sync" above) into one chronological list. A mirrored event shows a lock
   glyph and can't be tapped into — it's read-only through the Command
   Center (spec #1, user story 22); a Commitment keeps the same tap-to-edit
   and sync-status badge `PersonalCommitmentsView` has, and `CalendarView`
   can create/edit/delete Commitments the same way that screen does.
   `PersonalCommitmentsView` still exists as the Commitment-only screen —
   `CalendarView` is the "everything on my calendar" view on top of it, not
   a replacement.
5. `AutomationLogView` (ticket #8) is read-only, like `DeadlinesView`: recent
   `AutomationLog` entries, most recent first, with the most recent sync
   failure (if any) shown as a banner at the top of the screen rather than
   only visible if it's still recent enough to also appear further down the
   list — see "Automation Log" above.

The backend's `PCCTask` model and the client's `PCCTask` struct are named
`PCCTask` in Swift, not `Task` — that would shadow `_Concurrency.Task`
throughout their targets. The domain term "Task" is what appears in the API
paths/JSON and the UI text.

It has been verified with `swift build --target PCCUI` (type-checks and links,
including the ticket #18 Sprint UI and the `ProjectsView` navigation change
above) but not run in a simulator or on-device.
