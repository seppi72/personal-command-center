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
| `GET` | `/v1/tasks` | List all Tasks; add `?projectID=` to scope to one Project, `?sprintID=` to scope to one Sprint, and/or `?courseID=` to scope to one Course |
| `POST` | `/v1/tasks` | Create a Task, Project-less and Course-less (`{ "title": "...", "notes": "..."? }`) |
| `PUT` | `/v1/tasks/:taskID` | Edit a Task's title/notes (`{ "title": "...", "notes": "..."? }`) |
| `DELETE` | `/v1/tasks/:taskID` | Delete a Task |
| `PUT` | `/v1/tasks/:taskID/complete` | Mark a Task complete |
| `PUT` | `/v1/tasks/:taskID/incomplete` | Mark a Task incomplete |
| `PUT` | `/v1/tasks/:taskID/project` | Assign/move/remove a Task's Project (`{ "projectID": "..."? }`, omit or `null` to remove) — clears the Task's Sprint if it moves to a different Project, and clears the Task's Course outright (a Task belongs to at most one of {Project, Course} — ADR-0003) |
| `PUT` | `/v1/tasks/:taskID/deadline` | Attach/change/remove a Task's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `PUT` | `/v1/tasks/:taskID/sprint` | Assign/move/remove a Task's Sprint (`{ "sprintID": "..."? }`, omit or `null` to remove) — rejects a Sprint that doesn't belong to the Task's current Project |
| `PUT` | `/v1/tasks/:taskID/course` | Assign/move/remove a Task's Course (`{ "courseID": "..."? }`, omit or `null` to remove) — clears the Task's Project and Sprint outright, the mirror image of `.../project` (ADR-0003, ticket #20) |
| `GET` | `/v1/sprints` | List a Project's Sprints — `?projectID=` is required |
| `POST` | `/v1/sprints` | Create a Sprint within a Project (`{ "projectID": "...", "name": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>" }`) |
| `PUT` | `/v1/sprints/:sprintID` | Edit a Sprint's name/dates (`{ "name": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>" }`) |
| `DELETE` | `/v1/sprints/:sprintID` | Delete a Sprint |
| `PUT` | `/v1/projects/:projectID/deadline` | Attach/change/remove a Project's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `GET` | `/v1/deadlines` | Every Task, Project, and Course together, ordered by Deadline proximity (undated items included, sorted last) |
| `GET` | `/v1/personal-commitments` | List all Personal Commitments |
| `POST` | `/v1/personal-commitments` | Create a Personal Commitment (`{ "title": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>", "recurrenceRule": "..."? }`) and push it to CalDAV |
| `PUT` | `/v1/personal-commitments/:commitmentID` | Edit a Personal Commitment (same body as create) and re-push it to CalDAV |
| `DELETE` | `/v1/personal-commitments/:commitmentID` | Delete a Personal Commitment and remove its CalDAV event |
| `GET` | `/v1/calendar-events` | List every mirrored external Calendar event (read-only — no create/update/delete; see "Calendar sync" below) |
| `GET` | `/v1/automation-logs` | Recent `AutomationLog` entries, most recent first, plus the most recent sync failure (if any) singled out (read-only; see "Automation Log" below) |
| `GET` | `/v1/courses` | List all Courses |
| `POST` | `/v1/courses` | Create a Course (`{ "name": "...", "termMonth": 1-12, "termYear": ... }`) |
| `PUT` | `/v1/courses/:courseID` | Edit a Course's name/Term (same body as create) |
| `DELETE` | `/v1/courses/:courseID` | Delete a Course |
| `PUT` | `/v1/courses/:courseID/deadline` | Attach/change/remove a Course's Deadline (`{ "dueDate": "<ISO 8601>"? }`, omit or `null` to remove) |
| `GET` | `/v1/time-entries` | List all Time Entries; add any combination of `?taskID=`/`?projectID=`/`?clientID=`/`?courseID=` to scope to one container |
| `POST` | `/v1/time-entries` | Create a Time Entry (`{ "startDate": "<ISO 8601>", "endDate": "<ISO 8601>", "notes": "..."?, "taskID"/"projectID"/"clientID"/"courseID": "..." }`, exactly one of the last four required) |
| `PUT` | `/v1/time-entries/:timeEntryID` | Edit a Time Entry (same body as create, replacing every field including its container) |
| `DELETE` | `/v1/time-entries/:timeEntryID` | Delete a Time Entry |
| `GET` | `/v1/time-entries/timer` | The currently running timer, or `null` if none — server-side state, visible from any device (ticket #28) |
| `POST` | `/v1/time-entries/timer/start` | Start a timer with `startDate = now` (`{ "taskID"/"projectID"/"clientID"/"courseID": "..." }`, exactly one required); fails if one is already running |
| `PUT` | `/v1/time-entries/timer/stop` | Stop the running timer into a completed Time Entry (`endDate = now`); 404 if none is running |
| `PUT` | `/v1/time-entries/timer/cancel` | Cancel the running timer outright — deletes it with no saved record; 404 if none is running |
| `GET` | `/v1/work-hours` | The Work Hours rollup (`?groupBy=day\|project\|client\|task\|course`, `?start=`/`?end=` both required, `<ISO 8601>`, range is `[start, end)`) — see "Work Hours" below |
| `GET` | `/v1/accounts` | List all Accounts with their Balance |
| `POST` | `/v1/accounts` | Create an Account (`{ "name": "...", "type": "checking\|savings\|cash\|creditCard\|investment\|loan", "openingBalance": <number> }`) |
| `PUT` | `/v1/accounts/:accountID` | Edit an Account's name/type (`{ "name": "...", "type": "..." }`) — `openingBalance` is immutable, see "Accounts" below |
| `DELETE` | `/v1/accounts/:accountID` | Delete an Account |

Deleting a Project doesn't delete its Tasks — they become Project-less. Deleting a Client doesn't delete its Projects — they become Client-less, the same orphaning shape. Deleting a Task/Project/Client/Course that a Time Entry still references is rejected outright (ticket #29) — a Time Entry can't legally exist container-less, so the owner must reassign or delete those Time Entries first (see "Time Entries" below).

### Clients (ticket #17)

A Client (`CONTEXT.md`) sits above Project, not beside it — created directly by the owner, since there's no external source of "you have a new client" to auto-detect one from. `ClientController` is a plain CRUD surface, same shape as `ProjectController`'s name-only create/edit. `ProjectController.setClient` (`PUT /v1/projects/:projectID/client`) assigns, moves, or removes a Project's Client — the same "one write handles all three ACs" shape `TaskController.assignProject` already has for a Task's Project.

Both the backend model and the client-side struct are named `PCCClient` in Swift, not `Client` — that would collide with Vapor's own `Client` protocol (`app.client`/`req.client`) server-side, the same problem `PCCTask` sidesteps for `_Concurrency.Task`. For the same reason, the backend's Client JSON response type is `PCCClientResponse`, not `ClientResponse` — Vapor already declares its own `ClientResponse` (the response type of `app.client`'s HTTP calls), so the unqualified name is ambiguous even though only one is ever in scope for a JSON body. The domain term "Client" is what shows up everywhere that matters — the `schema`, the JSON API, docs, and UI text.

### Sprints (ticket #18)

A Sprint (`CONTEXT.md`) is a time-boxed iteration within one Project that Tasks can be grouped into. A Project's use of Sprints is optional, but a Sprint itself is scoped to the Project it was created in for its lifetime — it doesn't move to a different Project, so `SprintController` never exposes a way to reassign a Sprint's Project (`UpdateSprintRequest` carries only `name`/`startDate`/`endDate`, not `projectID`). Because a Sprint has no meaning outside a Project, `GET /v1/sprints` requires `?projectID=` — unlike `GET /v1/clients` or `GET /v1/projects`, there's no "list all Sprints" story.

`Sprint.project` is a non-optional `@Parent`, not an `@OptionalParent` like `PCCTask.project` — a Sprint cannot exist without exactly one owning Project. That's why `CreateSprint`'s `project_id` foreign key uses `.cascade`, not `.setNull`: deleting a Project deletes its Sprints along with it, the opposite tradeoff from `AddClientToProject`'s `.setNull` (where the child, Project, *can* exist without the parent). A Task's relationship to its Sprint is the usual optional one, though — `AddSprintToPCCTask`'s `sprint_id` is nullable with `.setNull`, so deleting a Sprint makes its Tasks Sprint-less rather than deleting them, the same orphaning shape `CreatePCCTask`'s `project_id` already has for a deleted Project.

`TaskController.assignSprint` (`PUT /v1/tasks/:taskID/sprint`) rejects a Sprint that doesn't belong to the Task's *current* Project — checked by comparing `sprint.$project.id` against `task.$project.id`, which also correctly rejects any Sprint for a currently Project-less Task, since no Sprint's `project.id` can equal `nil`. `TaskController.assignProject` (`PUT /v1/tasks/:taskID/project`) clears the Task's Sprint whenever the incoming `projectID` differs from its current one (including moving to Project-less) — a Sprint that belonged to the old Project no longer applies once the Task moves. Moving a Task to the Project it's already in leaves its Sprint untouched.

### Courses (ticket #19)

A Course (`CONTEXT.md`) is a container of related Tasks/Deadlines for a single school class, e.g. "CS 301" — analogous to how a Project contains personal Tasks, down to optionally carrying its own Deadline the same way a Project can (`PUT /v1/courses/:courseID/deadline` mirrors `ProjectController.setDeadline` exactly). Created directly by the owner each Term, not auto-detected; the Tasks/Deadlines inside it are what auto-populate later, from a school data source. `CourseController` is a plain CRUD surface, same shape as `ProjectController`'s/`ClientController`'s — `GET /v1/courses` lists every Course with no scoping, since a Course is top-level, not nested under anything.

Term (the month and year a Course belongs to, e.g. "September 2026") is modeled as two required integers, `termMonth`/`termYear`, rather than a `Date` — there's no real day-of-month in a Term, and fabricating one (e.g. the 1st) would misrepresent the domain. The JSON shape keeps `termMonth`/`termYear` flat on `SaveCourseRequest`/`CourseResponse` rather than a nested `{ "term": { ... } }` object, matching every other DTO in this codebase.

Unlike `PCCClient`/`PCCTask`, `Course` collides with nothing in Vapor/the stdlib, so the model, response DTO, and PCCUI struct are all named plainly `Course`.

### Task↔Course assignment + Project/Course exclusivity (ticket #20)

A Task belongs to at most one of {Project, Course}, never both (`docs/adr/0003-task-belongs-to-project-xor-course.md`) — the two are alternate containers of the same kind, not orthogonal tags. `TaskController.assignProject`/`assignCourse` (`PUT /v1/tasks/:taskID/project`/`.../course`) enforce the exclusivity at write time: setting a non-nil `projectID` clears the Task's `courseID` outright, and setting a non-nil `courseID` clears both `projectID` and, transitively, `sprintID` (a Sprint is scoped to a Project, so a Project-less Task can't reference one — the same `.../project` already does when a Task moves to a *different* Project, ticket #18). *Removing* a Project or Course (`projectID`/`courseID: null`) leaves the other side untouched, since a Task with one never has the other to begin with. `AddCourseToPCCTask`'s `course_id` foreign key is `.setNull`, matching `project_id`/`sprint_id` — deleting a Course orphans its Tasks (Course-less) rather than deleting them. `GET /v1/tasks` accepts `?courseID=` alongside `?projectID=`/`?sprintID=`, and `GET /v1/deadlines` folds in Courses' own Deadlines (a third `DeadlineItemResponse.Kind` alongside `.task`/`.project`) — Course-scoped Tasks needed no special handling there, since the Task query was never scoped by container to begin with.

Unlike `?projectID=`/`?sprintID=` on `GET /v1/tasks`, `POST /v1/tasks` does *not* gain a `courseID` field — a Task is created Project-less and Course-less either way, matching how it was already created Project-less before this ticket (assignment is `assignProject`'s own job, not `create`'s); `courseID`/`projectID` join the Task model's own initializer (used by tests and internal construction) the same way `projectID` already had.

### Time Entries (ticket #27)

A Time Entry (`CONTEXT.md`) is canonical (no external timesheet system exists to mirror), and attaches to exactly one of Task, Project, Client, or Course — required, never none, never more than one (`docs/adr/0004-time-entry-container-includes-course.md`), the same alternate-container shape as a Task's Project/Course exclusivity (ADR-0003) extended to a fourth peer. Unlike `TaskController`, which creates a Task container-less and assigns it via separate follow-up endpoints, `TimeEntryController.create`/`update` take the container inline in `SaveTimeEntryRequest` — a Time Entry's container is mandatory from the start, so there's no valid "not yet assigned" state to create into.

`TimeEntryController.validatedContainer` rejects a request with zero or more than one of `taskID`/`projectID`/`clientID`/`courseID` set, then `verifyContainerExists` confirms the one given id actually resolves to a row before the Time Entry is saved. `verifyNoOverlap` rejects a span that strictly overlaps an existing Time Entry's span — touching boundaries (one ends exactly when another starts) are allowed, so the check uses strict `<`/`>` rather than `<=`/`>=`. The overlap check is global, not scoped to the same container: Work Hours tracks one person's time, who can only be doing one thing at once, regardless of which Task/Project/Client/Course each span is logged against. `update` excludes the Time Entry being edited from its own overlap check, so editing a Time Entry without changing its span (e.g. only its notes) doesn't reject against itself.

`TimeEntry`'s four foreign keys (`task_id`/`project_id`/`client_id`/`course_id`) are all optional at the Fluent/Postgres level — only one is ever non-nil for a given row — but each uses `.cascade` in `CreateTimeEntry`, not `.setNull` like `PCCTask.project`/`course`: since a Time Entry can't legally exist container-less, a *database-level* delete of its Task/Project/Client/Course would take it down too. In practice that cascade is a fallback only — since ticket #29, `TaskController`/`ProjectController`/`ClientController`/`CourseController.delete` each reject the delete outright while a Time Entry still references it (see "Blocking deletion with referencing Time Entries" below), so the API never actually reaches the cascade.

### Live Timer (ticket #28)

A live timer is a `TimeEntry` row that hasn't been stopped yet — `endDate == nil` (`TimeEntry.isRunning`) — rather than a separate table, so stopping one is just setting the same `end_date` column manual entries already use. `end_date` was `.required` since `CreateTimeEntry`; `MakeTimeEntryEndDateOptional` drops that `NOT NULL` constraint directly via `SQLDatabase` (Fluent's schema builder has no "make an existing column nullable" operation of its own).

`POST /v1/time-entries/timer/start` rejects if a timer is already running (checked before the container is even decoded), then validates its container the same way `create` does (`TimeEntryController.validatedContainer`, refactored to take the four ids directly so both `SaveTimeEntryRequest` and `StartTimerRequest` can share it) and saves a `TimeEntry` with `startDate = now`, no `endDate`. `GET /v1/time-entries/timer` queries fresh from the database on every call — genuinely server-side state, not per-connection — and returns a literal JSON `null` when none is running, since `TimeEntryResponse?` can't be returned directly from a Vapor route handler (no `AsyncResponseEncodable` conformance for `Optional`); the response is built by hand instead. `PUT /v1/time-entries/timer/stop` sets `endDate = now` under the same zero-duration/overlap validation as `update` — nothing is mutated or saved until both checks pass, so a rejected stop leaves the timer running, unchanged. A running timer's `NULL end_date` is treated as open-ended, not excluded, by that same overlap check — `verifyNoOverlap`'s filter is `endDate IS NULL OR endDate > startDate` — so a manual entry (or another `create`/`update`) that begins before an already-running timer still overlaps it, the same "only doing one thing at once" invariant ticket #27 already enforces between two completed entries. `PUT /v1/time-entries/timer/cancel` deletes the running entry outright, no saved record. No cap or warning is enforced on how long a timer has been running.

### Work Hours (ticket #25)

Work Hours (`CONTEXT.md`) is the aggregate view over Time Entries — totals grouped by day, or by one of Time Entry's four containers, over `[start, end)`. `GET /v1/work-hours` is one read-only endpoint serving all five `groupBy` values, since they share the same query/validation shape and differ only in how the same underlying Time Entries get bucketed; only completed Time Entries (`endDate != nil`) starting in range are counted — a running live timer contributes nothing until it's stopped. `WorkHoursController.validatedRange` parses `start`/`end` from the query string by hand with `ISO8601DateFormatter` rather than decoding straight into `Date`: Vapor's query-string decoder defaults `Date` to seconds-since-1970, unlike its JSON-body decoder (what every other date in this API relies on defaulting to ISO 8601), so a plain `req.query[Date.self, at:]` here would silently expect a different wire format than everywhere else.

`groupBy=day` is dense — one row per calendar day in range (`Calendar.current.startOfDay`, this process's own local timezone — there's no owner-timezone concept elsewhere in the domain yet), including a day with nothing logged. An entry spanning midnight counts entirely toward its `startDate`'s day rather than being split. The other four `groupBy` values are sparse — a container with a zero total in range doesn't appear as a row at all — and each row carries the entity's id and name (`{projectID, projectName, totalSeconds}` etc.) so `WorkHoursView` doesn't need a second round-trip to label it.

Project/Client/Course totals fold transitively (`docs/adr/0005-work-hours-rollup-transitive-fold.md`): a Project's total is its own direct-to-Project entries plus every entry logged against any Task belonging to it; a Client's total is its own direct entries plus each of its Projects' already-folded totals; a Course's total is its own direct entries plus every entry logged against any Task belonging to it. A Task's total is direct entries only — nothing folds into a Task. Sprint isn't a sixth `groupBy` dimension: a Sprint's entries already fold into their Project via the owning Task's `project_id`. `WorkHoursController.containerRows` loads every Task/Project/Client/Course regardless of `groupBy` (a personal, single-owner dataset) rather than only the ones a Time Entry happens to reference directly — a Client's fold needs *every* one of its Projects' totals, including a Project with no Time Entries of its own, or an indirectly-folded Client total could come out short.

Since each `groupBy`'s row has genuinely different JSON keys, `WorkHoursRow` (backend) encodes itself by hand rather than relying on `Codable`'s synthesized conformance for one struct — the same "build the response by hand" move `TimeEntryController.getTimer` already makes for its own not-one-fixed-shape response. The PCCUI-side `WorkHoursRow` mirrors this the other way: one `Decodable` struct with optional `date`/`id`/`name` fields, whichever one's non-`nil` telling `WorkHoursView` how to label a row, since a given response only ever contains rows of the one `groupBy` kind that was requested.

### Accounts (ticket #36)

An Account (`CONTEXT.md`) is a named store of money the owner tracks — Checking, Savings, Cash, Credit Card, Investment, or Loan — created directly by the owner, not auto-detected (`docs/adr/0006-manual-entry-over-bank-aggregation-for-finances.md`). `AccountController` is a plain CRUD surface, same shape as `ProjectController`/`ClientController`, with one deliberate deviation from this codebase's usual PUT-replaces-everything convention: `UpdateAccountRequest` carries `name`/`type` only, with no `openingBalance` field at all — an Account's opening balance is set once at creation and never editable after (`docs/adr/0007-computed-balance-over-reconciliation.md`).

`AccountType`'s asset/liability classification (Checking/Savings/Cash/Investment = asset, Credit Card/Loan = liability) is a fixed mapping, not owner-configurable — `AccountResponse.classification` is a computed property derived from `type`, never a field a request can set independently of it. `AccountResponse.balance` is `openingBalance` plus every Transaction logged against the Account, summed via `Transaction.netAmount`/`netAmountsByAccount` (ticket #37). `Account.delete` rejects while any Transaction still references it (ticket #38, below) rather than orphaning or cascading it away.

### Blocking deletion with referencing Time Entries (ticket #29)

`TaskController`/`ProjectController`/`ClientController`/`CourseController.delete` each query for a Time Entry referencing the row being deleted and reject with a clear error if one exists, before ever calling `.delete()` — the owner must reassign or delete those Time Entries first, rather than the delete either orphaning the Time Entry (as `Client` → `Project` deletion still does) or silently taking it down too. `SprintController.delete` is unaffected — Sprint is not a Time Entry container.

### Blocking Account deletion while Transactions reference it (ticket #38)

`AccountController.delete` follows the same shape ticket #29 already gave `TaskController`/`ProjectController`/`ClientController`/`CourseController`: it queries for a Transaction referencing the Account being deleted and rejects with a clear error if one exists, before ever calling `.delete()` — the owner must reassign or delete those Transactions first. This is a deliberate reversal of ticket #36's original note that no such guard existed yet; it applies now that Transaction (ticket #37) exists to reference an Account.

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
ticket #17), a Sprints section within the Project detail flow
(`ProjectDetailView` + `SprintsViewModel` + `URLSessionSprintsAPIClient`,
ticket #18), the Courses screen (`CourseView` + `CoursesViewModel` +
`URLSessionCoursesAPIClient`, ticket #19), the Time Entries screen
(`TimeEntriesView` + `TimeEntriesViewModel` +
`URLSessionTimeEntriesAPIClient`, ticket #27), the live-timer control
(`TimerView` + `TimerViewModel`, sharing the same
`URLSessionTimeEntriesAPIClient`, ticket #28), the Work Hours rollup
screen (`WorkHoursView` + `WorkHoursViewModel` +
`URLSessionWorkHoursAPIClient`, ticket #25), and the Accounts screen
(`AccountsView` + `AccountsViewModel` + `URLSessionAccountsAPIClient`,
ticket #36), built as a plain SPM target with no Vapor/Fluent dependency.
It isn't wrapped in an Xcode app target yet — no Xcode is set up in this
environment. To use it:

1. Create the Mac and/or iOS App targets in Xcode (`File > New > Project`).
2. Add this repository as a local Swift package dependency and link `PCCUI`.
3. From each app's entry point, construct a `URLSessionProjectsAPIClient`,
   `URLSessionTasksAPIClient`, `URLSessionDeadlinesAPIClient`,
   `URLSessionPersonalCommitmentsAPIClient`,
   `URLSessionMirroredCalendarEventsAPIClient`,
   `URLSessionAutomationLogsAPIClient`, `URLSessionClientsAPIClient`,
   `URLSessionSprintsAPIClient`, `URLSessionCoursesAPIClient`,
   `URLSessionTimeEntriesAPIClient`, `URLSessionWorkHoursAPIClient`, and
   `URLSessionAccountsAPIClient` with the backend's base URL and the
   device's bearer token. Wrap each in its
   matching view model to show `ProjectsView(viewModel:)`,
   `TasksView(viewModel:)` (pass `scopedProjectID` to scope the screen to
   one Project, or omit it to list every Task), `DeadlinesView(viewModel:)`,
   `PersonalCommitmentsView(viewModel:)`, `CalendarView(viewModel:)`,
   `AutomationLogView(viewModel:)`, `ClientsView(viewModel:)`,
   `CourseView(viewModel:)`, `TimeEntriesView(viewModel:)`,
   `TimerView(viewModel:)` (the last two share one
   `URLSessionTimeEntriesAPIClient` between a `TimeEntriesViewModel` and a
   `TimerViewModel`), `WorkHoursView(viewModel:)`, and
   `AccountsView(viewModel:)`. A Task
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
   scope ticket #17 drew around Project-Client assignment. `TasksViewModel`
   now also takes a `coursesClient: CoursesAPIClient` in its `init`
   (alongside `projectsClient`) and an optional `scopedCourseID`, mirroring
   `scopedProjectID` — the Course detail flow's counterpart (ticket #20).
   `TaskFormSheet`'s single Project picker is now a Project picker *and* a
   Course picker: picking one clears the other (ADR-0003), matching
   `TaskController.assignProject`/`assignCourse`'s server-side exclusivity.
   `CoursesViewModel` now also takes `tasksClient: TasksAPIClient` and
   `projectsClient: ProjectsAPIClient` in its `init`, used by its
   `makeTasksViewModel(for:)` factory (ticket #20, mirrors
   `ProjectsViewModel.makeSprintsViewModel`). Tapping a Course row now
   navigates into `CourseDetailView` instead of opening the edit sheet
   directly — the same evolution `ProjectsView` went through in ticket #18 —
   with editing moved to that screen's own toolbar "Edit" button.
   `CourseDetailView` shows the Course's name/Term/due date read-only above a
   "Tasks" section: each Task's completion toggle, title, and due date, with
   add/edit/complete/delete via the same `TaskFormSheet`/`TasksViewModel`
   the top-level Tasks screen uses (just scoped to that Course), rather than
   a separate, duplicated implementation. `DeadlinesView`'s row glyph now has
   a third case (`"graduationcap"`) for a Course's own Deadline, alongside
   the existing Task/Project glyphs. `TimeEntriesView` (ticket #27) lists
   Time Entries with add/edit/delete via `TimeEntryFormSheet`, a container
   picker with the same "pick one, clears the other three" shape as
   `TaskFormSheet`'s Project/Course pair; a row with no `endDate` yet (a
   running timer — ticket #28) shows a "Running" label, and editing one
   defaults its end-time field to "now" rather than crashing on a nil value.
   `TimerView` (ticket #28) is a separate, minimal control — the currently
   running timer (what it's attached to, and since when) with Stop/Cancel
   buttons, or a container picker and Start button when none is running —
   backed by its own `TimerViewModel`, constructed from the same
   `URLSessionTimeEntriesAPIClient` plus the four picker-data clients
   `TimeEntriesViewModel` already takes.
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
6. `WorkHoursView` (ticket #25) is a plain `List` of `{name, total}` rows —
   no chart, matching every other screen's minimal convention — above a
   `Picker` for the five `groupBy` values and two `DatePicker`s for the
   range, all sharing one `WorkHoursViewModel`. Every control change
   reloads immediately (no separate "Apply" step, unlike a form with
   unsaved state to submit); opening the screen defaults to `groupBy = .day`
   and the current week, Monday through now, and loads right away via
   `.task`. A row's duration is formatted as plain "1h 30m"/"45m" text —
   see "Work Hours" above for the backend rollup this screen renders.

The backend's `PCCTask` model and the client's `PCCTask` struct are named
`PCCTask` in Swift, not `Task` — that would shadow `_Concurrency.Task`
throughout their targets. The domain term "Task" is what appears in the API
paths/JSON and the UI text.

It has been verified with `swift build --target PCCUI` (type-checks and links,
including the ticket #18 Sprint UI, the ticket #19 Course screen, the
ticket #20 Task↔Course picker plus `CourseDetailView`'s Tasks section, the
ticket #27 Time Entries screen, the ticket #28 `TimerView` live-timer
control, and the ticket #25 `WorkHoursView` rollup screen) but not run in a
simulator or on-device.
