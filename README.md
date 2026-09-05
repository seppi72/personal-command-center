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
| `NOTIFICATION_SCAN_INTERVAL_SECONDS` | `300` | How often the recurring overdue-Deadline scan (ticket #47) reconciles the Notification queue against overdue Tasks/Projects/Courses. Not read/used when `swift test` runs — see "Notifications" below |

### CalDAV setup

Personal Commitments (ticket #6) push to a specific iCloud calendar via CalDAV (`docs/adr/0002-caldav-over-eventkit-for-calendar-sync.md`). `ICloudCalDAVClient` targets one calendar collection URL directly — it does not perform the CalDAV principal/calendar-home discovery dance (`PROPFIND` against `https://caldav.icloud.com`) that resolves an Apple ID into that URL. Until `CALDAV_CALENDAR_URL`/`CALDAV_USERNAME`/`CALDAV_APP_SPECIFIC_PASSWORD` are set, every push fails (logged to `AutomationLog`, not silently dropped — see "Personal Commitments" below) rather than being skipped.

To find your calendar's collection URL: generate an app-specific password at [appleid.apple.com](https://appleid.apple.com), then issue a CalDAV `PROPFIND` against `https://caldav.icloud.com/` with that Apple ID/password (e.g. via a CalDAV-aware client, or `curl -u "<apple-id>:<app-specific-password>" -X PROPFIND ...` following the `calendar-home-set` property) to locate the calendar you want Commitments pushed to, of the form `https://pXX-caldav.icloud.com/<numeric-id>/calendars/<calendar-name>/`.

## Deployment (daily use on this Mac)

The "Local setup" steps above are for developing against the backend. For
actually using the app day-to-day, `scripts/redeploy.sh` is the "change
code at will, then redeploy" entrypoint (`docs/adr/0010`):

```sh
./scripts/redeploy.sh
```

Each run rebuilds `App` and `PCCDesktop` in release mode, then:

- (Re)starts the backend as a `launchd` LaunchAgent
  (`com.seppi72.personal-command-center`, `~/Library/LaunchAgents/`) —
  it starts automatically at login and restarts itself if it crashes, so
  there's no terminal window to keep open. Bound to `127.0.0.1` only; it's
  not reachable from other devices (see ADR-0010 on why, and when to
  revisit that).
- Refreshes `/Applications/PCCDesktop.app` — a hand-built (unsigned,
  no Xcode involved) `.app` bundle wrapping the `PCCDesktop` executable, so
  it's launchable from Spotlight/Launchpad/Dock like a normal Mac app
  rather than a binary you `cd` to and run from Terminal. Quit and
  relaunch it after a redeploy to pick up the new build — the bundle's
  files are replaced on disk, but a still-running instance keeps its old
  copy loaded until relaunched.

The backend's secrets (`AUTH_TOKENS`, and `CALDAV_*` if you wire that up
later) live in `~/.pcc.env`, **outside this repo** — `redeploy.sh` creates
it with a default `AUTH_TOKENS=mac-token` the first time it runs, and
leaves it alone on every run after that; edit it by hand for anything
beyond the default. `scripts/run-backend.sh` (what the LaunchAgent
actually execs) sources this file before launching `App`.

Useful commands once deployed:

```sh
# Check whether the backend service is running
launchctl print "gui/$(id -u)/com.seppi72.personal-command-center" | grep state

# Tail backend logs
tail -f ~/Library/Logs/personal-command-center/backend.log
tail -f ~/Library/Logs/personal-command-center/backend.error.log

# Stop the backend service (redeploy.sh will restart it on the next run)
launchctl bootout "gui/$(id -u)/com.seppi72.personal-command-center"
```

Not covered by this setup (deliberately deferred, see ADR-0010): Postgres
backups (only brew's on-disk data-directory durability, no snapshot/export
routine), CalDAV configuration (Personal Commitments pushes stay a
documented no-op until you configure it — see "CalDAV setup" above), and
LAN/iOS reachability (backend is Mac-local only for now).

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
| `GET` | `/v1/personal-commitments` | List all Personal Commitments; add `?courseID=` to scope to one Course |
| `POST` | `/v1/personal-commitments` | Create a Personal Commitment (`{ "title": "...", "startDate": "<ISO 8601>", "endDate": "<ISO 8601>", "recurrenceRule": "..."?, "courseID": "..."? }`) and push it to CalDAV |
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
| `GET` | `/v1/net-worth` | Current Net Worth: every asset Account's Balance minus every liability Account's Balance, computed live |
| `GET` | `/v1/net-worth/trend` | Net Worth trend (`?start=`/`?end=` both required, `<ISO 8601>`, range is `[start, end)`) — one dense row per day, each as of that day's end — see "Finances Reporting" below |
| `GET` | `/v1/expenses-per-day` | Expense totals across every Account regardless of Type (`?start=`/`?end=` both required) — one dense row per day |
| `GET` | `/v1/accounts/:accountID/balance-history` | One Account's Balance over `[start, end)` (`?start=`/`?end=` both required) — one dense row per day, each as of that day's end |
| `GET` | `/v1/accounts/:accountID/projected-balance` | One Account's Projected Balance (`?period=week\|month`) — `{ averageDailyNet, projectedBalance, period }` |
| `GET` | `/v1/categories` | List all Categories |
| `POST` | `/v1/categories` | Create a Category (`{ "name": "..." }`) |
| `PUT` | `/v1/categories/:categoryID` | Rename a Category (`{ "name": "..." }`) |
| `DELETE` | `/v1/categories/:categoryID` | Delete a Category — cascade-deletes its Subcategories, see "Categories/Subcategories" below |
| `GET` | `/v1/subcategories` | List a Category's Subcategories — `?categoryID=` is required |
| `POST` | `/v1/subcategories` | Create a Subcategory within a Category (`{ "categoryID": "...", "name": "..." }`) |
| `PUT` | `/v1/subcategories/:subcategoryID` | Rename a Subcategory (`{ "name": "..." }`) |
| `DELETE` | `/v1/subcategories/:subcategoryID` | Delete a Subcategory |
| `GET` | `/v1/notifications` | List undismissed Notifications, newest first (see "Notifications" below) |
| `POST` | `/v1/notifications/:notificationID/dismiss` | Dismiss a Notification — idempotent, no error on an already-dismissed row |

Deleting a Project doesn't delete its Tasks — they become Project-less. Deleting a Client doesn't delete its Projects — they become Client-less, the same orphaning shape. Deleting a Task/Project/Client/Course that a Time Entry still references is rejected outright (ticket #29) — a Time Entry can't legally exist container-less, so the owner must reassign or delete those Time Entries first (see "Time Entries" below).

### Clients (ticket #17)

A Client (`CONTEXT.md`) sits above Project, not beside it — created directly by the owner, since there's no external source of "you have a new client" to auto-detect one from. `ClientController` is a plain CRUD surface, same shape as `ProjectController`'s name-only create/edit. `ProjectController.setClient` (`PUT /v1/projects/:projectID/client`) assigns, moves, or removes a Project's Client — the same "one write handles all three ACs" shape `TaskController.assignProject` already has for a Task's Project.

Both the backend model and the client-side struct are named `PCCClient` in Swift, not `Client` — that would collide with Vapor's own `Client` protocol (`app.client`/`req.client`) server-side, the same problem `PCCTask` sidesteps for `_Concurrency.Task`. For the same reason, the backend's Client JSON response type is `PCCClientResponse`, not `ClientResponse` — Vapor already declares its own `ClientResponse` (the response type of `app.client`'s HTTP calls), so the unqualified name is ambiguous even though only one is ever in scope for a JSON body. The domain term "Client" is what shows up everywhere that matters — the `schema`, the JSON API, docs, and UI text.

### Sprints (ticket #18)

A Sprint (`CONTEXT.md`) is a time-boxed iteration within one Project that Tasks can be grouped into. A Project's use of Sprints is optional, but a Sprint itself is scoped to the Project it was created in for its lifetime — it doesn't move to a different Project, so `SprintController` never exposes a way to reassign a Sprint's Project (`UpdateSprintRequest` carries only `name`/`startDate`/`endDate`, not `projectID`). Because a Sprint has no meaning outside a Project, `GET /v1/sprints` requires `?projectID=` — unlike `GET /v1/clients` or `GET /v1/projects`, there's no "list all Sprints" story.

`Sprint.project` is a non-optional `@Parent`, not an `@OptionalParent` like `PCCTask.project` — a Sprint cannot exist without exactly one owning Project. That's why `CreateSprint`'s `project_id` foreign key uses `.cascade`, not `.setNull`: deleting a Project deletes its Sprints along with it, the opposite tradeoff from `AddClientToProject`'s `.setNull` (where the child, Project, *can* exist without the parent). A Task's relationship to its Sprint is the usual optional one, though — `AddSprintToPCCTask`'s `sprint_id` is nullable with `.setNull`, so deleting a Sprint makes its Tasks Sprint-less rather than deleting them, the same orphaning shape `CreatePCCTask`'s `project_id` already has for a deleted Project.

`TaskController.assignSprint` (`PUT /v1/tasks/:taskID/sprint`) rejects a Sprint that doesn't belong to the Task's *current* Project — checked by comparing `sprint.$project.id` against `task.$project.id`, which also correctly rejects any Sprint for a currently Project-less Task, since no Sprint's `project.id` can equal `nil`. `TaskController.assignProject` (`PUT /v1/tasks/:taskID/project`) clears the Task's Sprint whenever the incoming `projectID` differs from its current one (including moving to Project-less) — a Sprint that belonged to the old Project no longer applies once the Task moves. Moving a Task to the Project it's already in leaves its Sprint untouched.

### Courses (ticket #19)

A Course (`CONTEXT.md`) is a container of related Tasks/Deadlines for a single school class, e.g. "CS 301" — analogous to how a Project contains personal Tasks, down to optionally carrying its own Deadline the same way a Project can (`PUT /v1/courses/:courseID/deadline` mirrors `ProjectController.setDeadline` exactly). Created directly by the owner each Term, not auto-detected; its Tasks, Deadlines, Time Entries, and (ticket #56) Personal Commitments are entered the same way any other Task, Deadline, Time Entry, or Personal Commitment is — there's no accessible school data source to auto-populate them from, a deliberate decision, not a placeholder for a future sync (`docs/adr/0009-manual-entry-not-lms-integration-for-school.md`). `CourseController` is a plain CRUD surface, same shape as `ProjectController`'s/`ClientController`'s — `GET /v1/courses` lists every Course with no scoping, since a Course is top-level, not nested under anything.

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

`groupBy=day` is dense — one row per calendar day in range (`Calendar.current.startOfDay`, this process's own local timezone — there's no owner-timezone concept elsewhere in the domain yet), including a day with nothing logged. An entry spanning midnight counts entirely toward its `startDate`'s day rather than being split. The other four `groupBy` values are sparse — a container with a zero total in range doesn't appear as a row at all — and each row carries the entity's id and name (`{projectID, projectName, totalSeconds}` etc.) so the Work Hours rollup in `WorkView`/`SchoolView` doesn't need a second round-trip to label it.

Project/Client/Course totals fold transitively (`docs/adr/0005-work-hours-rollup-transitive-fold.md`): a Project's total is its own direct-to-Project entries plus every entry logged against any Task belonging to it; a Client's total is its own direct entries plus each of its Projects' already-folded totals; a Course's total is its own direct entries plus every entry logged against any Task belonging to it. A Task's total is direct entries only — nothing folds into a Task. Sprint isn't a sixth `groupBy` dimension: a Sprint's entries already fold into their Project via the owning Task's `project_id`. `WorkHoursController.containerRows` loads every Task/Project/Client/Course regardless of `groupBy` (a personal, single-owner dataset) rather than only the ones a Time Entry happens to reference directly — a Client's fold needs *every* one of its Projects' totals, including a Project with no Time Entries of its own, or an indirectly-folded Client total could come out short.

Since each `groupBy`'s row has genuinely different JSON keys, `WorkHoursRow` (backend) encodes itself by hand rather than relying on `Codable`'s synthesized conformance for one struct — the same "build the response by hand" move `TimeEntryController.getTimer` already makes for its own not-one-fixed-shape response. The PCCUI-side `WorkHoursRow` mirrors this the other way: one `Decodable` struct with optional `date`/`id`/`name` fields, whichever one's non-`nil` telling the rollup how to label a row, since a given response only ever contains rows of the one `groupBy` kind that was requested.

### Accounts (ticket #36)

An Account (`CONTEXT.md`) is a named store of money the owner tracks — Checking, Savings, Cash, Credit Card, Investment, or Loan — created directly by the owner, not auto-detected (`docs/adr/0006-manual-entry-over-bank-aggregation-for-finances.md`). `AccountController` is a plain CRUD surface, same shape as `ProjectController`/`ClientController`, with one deliberate deviation from this codebase's usual PUT-replaces-everything convention: `UpdateAccountRequest` carries `name`/`type` only, with no `openingBalance` field at all — an Account's opening balance is set once at creation and never editable after (`docs/adr/0007-computed-balance-over-reconciliation.md`).

`AccountType`'s asset/liability classification (Checking/Savings/Cash/Investment = asset, Credit Card/Loan = liability) is a fixed mapping, not owner-configurable — `AccountResponse.classification` is a computed property derived from `type`, never a field a request can set independently of it. `AccountResponse.balance` is `openingBalance` plus every Transaction logged against the Account, summed via `Transaction.netAmount`/`netAmountsByAccount` (ticket #37). `Account.delete` rejects while any Transaction still references it (ticket #38, below) rather than orphaning or cascading it away.

### Blocking deletion with referencing Time Entries (ticket #29)

`TaskController`/`ProjectController`/`ClientController`/`CourseController.delete` each query for a Time Entry referencing the row being deleted and reject with a clear error if one exists, before ever calling `.delete()` — the owner must reassign or delete those Time Entries first, rather than the delete either orphaning the Time Entry (as `Client` → `Project` deletion still does) or silently taking it down too. `SprintController.delete` is unaffected — Sprint is not a Time Entry container.

### Blocking Account deletion while Transactions reference it (ticket #38)

`AccountController.delete` follows the same shape ticket #29 already gave `TaskController`/`ProjectController`/`ClientController`/`CourseController`: it queries for a Transaction referencing the Account being deleted and rejects with a clear error if one exists, before ever calling `.delete()` — the owner must reassign or delete those Transactions first. This is a deliberate reversal of ticket #36's original note that no such guard existed yet; it applies now that Transaction (ticket #37) exists to reference an Account.

### Categories/Subcategories + Transaction tagging (ticket #39)

`CategoryController`/`SubcategoryController` are plain CRUD surfaces for Category/Subcategory (`CONTEXT.md`) — a Category is flat, same shape as `ClientController`; `GET /v1/subcategories` requires `?categoryID=`, same shape as `SprintController`'s required `?projectID=`, since a Subcategory has no meaning outside the Category it's scoped to. Deleting a Category cascade-deletes its Subcategories (`CreateSubcategory`'s `.cascade` FK, matching `CreateSprint`'s own `project_id`), and orphans (sets null on) rather than blocks any referencing Transaction's `categoryID`/`subcategoryID` (`AddCategoryToTransaction`'s `.setNull` FKs) — the opposite tradeoff from ticket #38's Account/Transaction guard, since a Transaction's Category is optional where its Account is required. Neither controller has an application-level delete guard the way `AccountController`/`ClientController` do; the database's own FK actions are what produce this behavior.

`Transaction` gains optional `categoryID`/`subcategoryID` fields, independent of each other rather than a single polymorphic container. The only consistency rule between them is enforced in `TransactionController.verifyCategoryAndSubcategory`: a `subcategoryID` requires a `categoryID` that's actually its parent — ruling out a Subcategory tagged without its Category, so the only valid states are neither, a Category alone, or a Category *and* its Subcategory together.

The Swift model backing Category is named `PCCCategory`, not `Category` — an unqualified `Category` collides with the Objective-C runtime's own `Category` typedef (`objc/runtime.h`, pulled in transitively through Foundation on Darwin), the same kind of collision `PCCTask`/`PCCClient` already sidestep. The domain term "Category" is what appears in the schema, JSON API, docs, and UI text; only the Swift symbol differs.

### Finances Reporting (ticket #40)

`FinancesReportingController` is read-only, computed rollups over Account/Transaction (`CONTEXT.md`'s Net Worth/Projected Balance entries) — mirroring Work Hours' "one feature family, several read endpoints sharing the same range/dense-day query pattern" shape (ticket #25), but as five separate routes rather than one `groupBy`-style endpoint, since the five figures don't share a single response shape the way Work Hours' five `groupBy` values do. `GET /v1/net-worth` is the current figure, computed live from every Account's Balance the same "load every Account, load every net Transaction sum once" shape `AccountController.index` already uses. The other four are each a dense `[start, end)` day-by-day series (`GET /v1/net-worth/trend`, `GET /v1/expenses-per-day`, `GET /v1/accounts/:accountID/balance-history`) or a computed figure for one Account and period (`GET /v1/accounts/:accountID/projected-balance`) — `validatedRange` parses `start`/`end` from the query string by hand with `ISO8601DateFormatter`, the same `WorkHoursController.validatedRange` reasoning (Vapor's query decoder defaults `Date` to seconds-since-1970, unlike its JSON-body decoder).

A day's Balance/Net-Worth figure is computed *as of that day's end* — `openingBalance` plus every Transaction dated on or before that day (`CONTEXT.md`) — not just Transactions dated inside `[start, end)`: a Transaction dated before `start` still carries forward into every day's figure, since a day's Balance is opening-balance-forward, not range-relative. `Self.cumulativeSeries` computes this efficiently: one Account query and one Transaction query total (not one Transaction query per Account, and not one query per day), sorting each Account's Transactions once and walking them alongside the dense day list with a single advancing index — an O(n log n) alternative to the O(days × transactions) a naive per-day filter-and-sum would cost. `netWorthTrend` reuses this per Account, weighting each Account's own series by `+1`/`-1` for asset/liability before summing across Accounts per day. `expensesPerDay` is *not* cumulative, unlike the other three — each day's figure is that day's own expense total, the same "one day's total, not a running total" shape `WorkHoursController.dayRows` already has for `groupBy=day`.

Projected Balance's `averageDailyNet` is net cash flow (income minus expenses, i.e. `Transaction.signedAmount`'s own sign) over the trailing 30 days, divided by 30; `projectedBalance` is today's Balance (via `Transaction.netAmount(forAccount:asOf:)` — the same as-of-day-end formula the dense series use, not `AccountController`'s plain `netAmount`, so there's one shared "Balance as of a day" definition across this whole feature rather than two that could disagree) plus `averageDailyNet` times the period's remaining days. "Remaining days" excludes today itself — today's own net cash flow is already baked into today's Balance, so counting it again as a projected day would double it — and is `tomorrow` through `Calendar.current.dateInterval(of: .weekOfYear/.month, for: today)`'s exclusive `end` (the start of the *next* period), that span being exactly "tomorrow through the period's last day, inclusive," clamped to zero rather than negative on a period's last day.

### Notifications (ticket #46)

A Notification (`CONTEXT.md`) is the owner's "needs you" queue: a surfaced item stored rather than live-computed, so it can be dismissed and stay dismissed. `NotificationController` is the read/dismiss surface — `GET /v1/notifications` returns undismissed (`isDismissed == false`) rows newest-first, and `POST /v1/notifications/:notificationID/dismiss` sets `isDismissed = true`, idempotently (dismissing an already-dismissed row succeeds as a no-op, not an error). There's no `DELETE` route — a dismissed row is never hard-deleted, kept for history the same way `AutomationLog` entries are.

`sourceType: String`/`sourceID: UUID` is the same open-ended plain-string pointer shape `AutomationLog` already uses for its own `subjectType`/`subjectID`, chosen over a Fluent `@Enum` since the set of source types will keep growing. The Swift model is named `PCCNotification`, not `Notification` — an unqualified `Notification` collides with Foundation's own `Notification`/`NotificationCenter` types, pulled in transitively on this platform, the same kind of collision `PCCTask`/`PCCCategory`/`PCCClient` already sidestep. The domain term "Notification" is what appears in the schema (`notifications`), the JSON API, docs, and UI text; only the Swift symbol differs.

**Overdue-Deadline scan (ticket #47)**: `NotificationScanService.scan()` runs on the same recurring-background-job shape as Calendar sync (`NotificationScanSchedule`, `NOTIFICATION_SCAN_INTERVAL_SECONDS`, default every 5 minutes; skipped when `swift test` runs, for the same "don't race test assertions against the same test database" reason `startCalendarSyncSchedule` skips during tests). Each run queries every Task (`isComplete == false`, past `dueDate`), Project, and Course with a past `dueDate` — reusing `DeadlineController`'s own "all three, flattened" query shape — and reconciles `PCCNotification` against that set: an overdue item with no currently-*open* Notification pointing at it gets one (`sourceType`/`sourceID` matching the item, `message` like `"Task 'Renew passport' is overdue"`), and an open Notification whose item is no longer in that set (completed, due date moved to the future, or deleted) gets dismissed automatically, via the same `isDismissed` flag an owner-initiated dismiss uses — there's no separate resolved-vs-dismissed-by-owner state. Dedup only ever checks *open* Notifications, never dismissed history: a Notification the owner dismisses while its item is still overdue is never itself reopened (that row stays dismissed for good), but a later scan is free to open a fresh row for the same still-overdue item. Tested by calling `NotificationScanService.scan()` directly against the real test database (`Tests/AppTests/NotificationScanServiceTests.swift`), the same seam `CalendarSyncServiceTests` uses for `CalendarSyncService` rather than exercising the schedule's loop.

**Automation-Log-failure hook (ticket #48)**: `CalendarSyncService`'s shared private `log` helper — the one every push/remove/pull outcome already funnels through — additionally creates a `PCCNotification` (`sourceType: "AutomationLog"`, `sourceID` the new `AutomationLog` row's own id, `message` the same `detail` text the log entry itself carries) inline, synchronously, whenever `outcome == .failure`. No scan or polling involved, and no dedup against past Notifications: every distinct failure gets its own new row regardless of earlier dismissals — a second, unrelated sync failure isn't silently swallowed just because an earlier one was already dismissed. Ticket #8's live "most recent failure" banner in `AutomationLogView` is untouched — this is additive to it, not a replacement.

### Personal Commitments

A Personal Commitment (`CONTEXT.md`) is canonical — the Command Center owns it, not the external Calendar — so create/edit/delete always succeed locally regardless of whether the CalDAV push succeeds. Each push (or removal) is attempted synchronously in the same request, and its outcome is written to `AutomationLog` and reflected in the Commitment's `syncStatus` (`pending` → `synced` or `failed`) in the response, rather than failing the request. The recurring sync job (below) is what retries a failed push later; browsing `AutomationLog` itself is ticket #8's.

### Personal Commitment ↔ Course link (ticket #56)

A Personal Commitment optionally links to a Course (`CONTEXT.md`) — a class meeting time logged as a Commitment, e.g. a recurring lecture (`docs/adr/0009-manual-entry-not-lms-integration-for-school.md`). It's a single optional link, not Time Entry's four-way container exclusivity (ADR-0004): nothing about a Commitment requires it to also attach to a Task/Project/Client, so `courseID` folds straight into the existing `SavePersonalCommitmentRequest`/`PersonalCommitmentResponse` shapes rather than a separate `PUT .../course` endpoint like Task/Course use. `PersonalCommitmentController.validatedCourseID` checks a non-nil `courseID` against `Course.find` before saving, throwing the same `Abort(.badRequest, reason: "no such Course")` `TaskController.assignCourse` throws for the identical case. `GET /v1/personal-commitments` accepts `?courseID=`, mirroring the same filter Task and Time Entry's own `index` already support.

The link is guarded the same way Time Entry's own containers and Finances' Accounts are (see "Blocking deletion with referencing Time Entries"/"Blocking Account deletion" above): `CourseController.delete` also rejects deleting a Course while any Personal Commitment still references it, alongside its existing Time Entry check. `AddCourseToPersonalCommitment`'s `course_id` foreign key is `.cascade`, not `.setNull` like `PCCTask.course` — since the guard already blocks the delete at the API level, this cascade is a database-level fallback only, never actually reached. The link is Command-Center-internal only: `CalendarSyncService.push` never serializes it into the pushed CalDAV event's title, description, or any other field.

### Calendar sync (ticket #7)

`CalendarSyncService.runScheduledSync` runs inside the Vapor process on a recurring interval (`CALENDAR_SYNC_INTERVAL_SECONDS`, default every 5 minutes), independent of whether the Mac or iOS app is open (spec #1, user story 23), and does two things each time:

1. **Pull**: fetches every event on the configured CalDAV calendar and upserts it (by external event id) into the read-only `MirroredCalendarEvent` cache, exposed at `GET /v1/calendar-events`. A repeated pull converges to whatever the external Calendar currently has rather than growing the cache forever.
2. **Push retry**: re-attempts the CalDAV push for every Personal Commitment not currently `synced` (i.e. `pending` or `failed`) — a safety net for a push that failed transiently, since `PersonalCommitmentController` already pushes synchronously on every create/edit and a Commitment stuck at `failed` would otherwise have no owner action to retry it.

A pull writes one `AutomationLog` entry (`actionType: "calendar.pull"`) per `MirroredCalendarEvent` it actually creates or changes — `subjectID` points at that row's own id, the same way a push's `subjectID` points at the Commitment it touched — and none for an event whose fields are unchanged since the last pull, so a quiet interval with nothing new doesn't flood the log; `lastSyncedAt` on every row (visible via `GET /v1/calendar-events`) is what confirms the pull itself is still running even when there's nothing to log. The one exception is a pull that fails before fetching any events at all, which has no affected row to log against and so logs once against a synthetic subject instead. A push retry writes one `personal_commitment.scheduled_sync` entry per Commitment it retries, the same way a controller-triggered push does. The job doesn't run when `swift test` runs (`app.environment == .testing`) — tests instead call `CalendarSyncService.pull()`/`pushPendingCommitments()`/`runScheduledSync()` directly against a `FakeCalDAVClient` and the real test database (`Tests/AppTests/CalendarSyncServiceTests.swift`), the same testing seam as `PersonalCommitmentTests`.

`ICloudCalDAVClient.fetchEvents()` (the pull's outbound call) issues a CalDAV `calendar-query` `REPORT` and hand-parses the multistatus XML response and each event's `.ics` body — same "hand-rolling event serialization/parsing" trade-off ADR-0002 accepted for the push side. Like `upsertEvent`/`deleteEvent`, it isn't itself covered by an automated test — only `CalendarSyncService`'s use of the `CalDAVClient` protocol is, via the fake.

### Automation Log (ticket #8)

`GET /v1/automation-logs` is the owner-facing read of `AutomationLog` (`CONTEXT.md`): every automated action's outcome, written by `CalendarSyncService`'s `push`/`remove`/`pull` today and whatever automation lands next. The response has two parts — `entries`, the 100 most recent log rows (most recent first), and `mostRecentFailure`, the single most recent entry with `outcome: "failure"` across the *entire* log, not just whichever of it happens to fall inside `entries`. Computing it separately is what keeps a failure from going unnoticed just because enough successes have piled up since to push it out of the recent list — the visible, singled-out failure state spec #1 asks for rather than one that silently scrolls out of view. `AutomationLogController` is read-only, same as `MirroredCalendarEventController` — no create/update/delete routes.

## Consumers (Mac/iOS)

### PCCHTTPTransport (ticket #54)

Every `URLSessionXAPIClient` below (17 of them, one per domain) composes a private `PCCHTTPTransport` rather than hand-rolling its own request construction, JSON encoding/decoding, query-string building, and status-code validation — the transport plumbing that used to be duplicated across all 17 files (and, before this ticket, only partially shared via a since-deleted `HTTPResponseValidation` that just covered the status check). Each domain client keeps its own public `init(baseURL:bearerToken:session:)` and its own `XAPIClientError` enum — `PCCHTTPTransport`'s `send`/`checkStatus` take `unexpectedResponse`/`serverError` closures so a domain client still throws its own error type rather than a shared one. `Tests/PCCUITests/PCCHTTPTransportTests.swift` covers `PCCHTTPTransport` itself (request/query construction, encoding, status validation, and a couple of full round-trips against a stubbed `URLProtocol`) — one of the pure-logic seams in `Tests/PCCUITests` that `PCCUI` does cover, the views themselves staying untested (`Package.swift`'s own comment on why).

### What `PCCUI` exposes today

`Sources/PCCUI` is a shared SwiftUI library, built as a plain SPM target with
no Vapor/Fluent dependency. It is not wrapped in an Xcode app target yet — no
Xcode is set up in this environment — so the entry points below are what a real
Mac/iOS target would instantiate. Every screen is one `public` `View` plus one
`public` view model plus one or more `URLSessionXAPIClient`s; nothing else in
the package is meant to be constructed directly by an app target.

| Screen | View | View model | API clients it needs |
| --- | --- | --- | --- |
| Overview | `OverviewView(viewModel:timerViewModel:onTapFinances:onTapProjects:onTapTasks:)` | `OverviewViewModel` + `TimerViewModel` | Tasks, Projects, Accounts, Transactions, Finances Reporting, Work Hours, Time Entries |
| Work | `WorkView(viewModel:timerViewModel:)` | `WorkViewModel` + `TimerViewModel` | Clients, Projects, Sprints, Tasks, Time Entries, Courses |
| School | `SchoolView(viewModel:)` | `SchoolViewModel` | Courses, Projects, Tasks, Time Entries, Personal Commitments |
| Deadlines (read-only) | `DeadlinesView(viewModel:)` | `DeadlinesViewModel` | Deadlines |
| Calendar | `CalendarView(viewModel:)` | `CalendarViewModel` | Personal Commitments, Mirrored Calendar Events, Courses |
| Personal Commitments | `PersonalCommitmentsView(viewModel:)` | `PersonalCommitmentsViewModel` | Personal Commitments, Courses |
| Accounts | `AccountsView(viewModel:)` | `AccountsViewModel` | Accounts |
| Transactions | `TransactionsView(viewModel:)` | `TransactionsViewModel` | Transactions, Accounts, Categories, Subcategories |
| Categories | `CategoriesView(viewModel:)` | `CategoriesViewModel` (+ `SubcategoriesViewModel` via `makeSubcategoriesViewModel(for:)`) | Categories, Subcategories |
| Finances Reporting | `FinancesReportingView(viewModel:)` | `FinancesReportingViewModel` | Finances Reporting, Accounts |
| Notifications | `NotificationsView(viewModel:)` | `NotificationsViewModel` | Notifications |
| Automation Log (read-only) | `AutomationLogView(viewModel:)` | `AutomationLogViewModel` | Automation Logs |

`TimerViewModel` is the one view model with no screen of its own: the live
timer control is rendered inside `WorkView` and `OverviewView`, and both take
it as a second parameter so one timer's state is shared rather than duplicated
per screen.

There is no longer a separate Clients, Projects, Tasks, Time Entries or Work
Hours screen — issue #89 merged all five into `WorkView` — and no separate
Courses screen — issue #90 replaced it with `SchoolView`. `WorkView` is a
single Client → Project → Sprint → Task tree with an hours rollup and a Time
Entries list beside it; `SchoolView` is the Course-side counterpart, with a
per-Course drill-down covering the Tasks and Meetings the old Course detail
screen showed. Overview totals both domains' hours (issue #91), the one place
the two are summed, since `WorkViewModel` filters Course-owned work out of its
tree and `SchoolViewModel` ignores everything else.

To use it:

1. Create the Mac and/or iOS App targets in Xcode (`File > New > Project`).
2. Add this repository as a local Swift package dependency and link `PCCUI`.
3. Construct the `URLSessionXAPIClient`s the table above names — each takes
   `(baseURL:bearerToken:session:)`, the backend's base URL and the device's
   bearer token — wrap them in their matching view models, and show the views.
   Clients are shareable across view models: one
   `URLSessionTimeEntriesAPIClient` can back `WorkViewModel`, `TimerViewModel`
   and `OverviewViewModel` at once.

Screen behavior worth knowing before wiring one up:

- A Task's or Project's Deadline is set/cleared from its own create/edit form
  inside `WorkView` (or `SchoolView`, for a Course's); `DeadlinesView` is a
  read-only sorted view of all three, its row glyph distinguishing Task,
  Project and Course Deadlines.
- `TaskFormSheet` has a Project picker *and* a Course picker where picking one
  clears the other (ADR-0003), matching
  `TaskController.assignProject`/`assignCourse`'s server-side exclusivity;
  `TimeEntryFormSheet`'s container picker has the same "pick one, clears the
  others" shape across its four containers.
- Assigning a Task's Sprint, and a Project's Client, is API-only (`PUT
  /v1/tasks/:taskID/sprint`, `PUT /v1/projects/:projectID/client`) — the UI
  shows the resulting names but has no picker for either.
- Each Commitment's sync status (pushed to CalDAV, or failed — see "CalDAV
  setup" above) shows as a badge on its row in both
  `PersonalCommitmentsView` and `CalendarView`.
- `CalendarView` merges Personal Commitments and mirrored external Calendar
  events into one chronological list. A mirrored event shows a lock glyph and
  can't be tapped into — it's read-only through the Command Center (spec #1,
  user story 22). `PersonalCommitmentsView` still exists as the
  Commitment-only screen; `CalendarView` is the "everything on my calendar"
  view on top of it, not a replacement. Both share
  `PersonalCommitmentFormSheet` (via `commitmentEditingSheets`), whose Course
  picker is optional and standalone — unlike `TaskFormSheet`'s Project/Course
  pair, nothing else on the form is mutually exclusive with it (ticket #56).
- `AutomationLogView` and `NotificationsView` are read-only lists of
  backend-authored rows; the former shows the most recent sync failure as a
  banner at the top rather than only where it falls in the list, the latter
  dismisses a Notification via swipe-to-delete.
- Every dashboard/report screen reloads immediately on any control change (no
  separate "Apply" step, unlike a form with unsaved state to submit).
  `WorkView`/`SchoolView` default to the current week, `FinancesReportingView`
  to the trailing 30 days — read more informatively as a trend.
- `FinancesReportingView` uses SwiftUI's native `Charts` framework, the only
  use of it anywhere in `PCCUI`, rather than a third-party charting dependency.
  Its sections — Net Worth (figure plus trend chart), Account Balance (an
  Account picker plus a history chart), expenses per day, and Projected
  Balance (a week/month picker, as text rather than a chart) — share one
  `start`/`end` `DatePicker` pair, while the Account and period pickers reload
  only their own two sections (`loadSelectedAccountFigures`).
- `CategoriesView` lists Categories with add/edit/delete; tapping one opens a
  detail screen with its own Subcategories section, built from
  `CategoriesViewModel.makeSubcategoriesViewModel(for:)`. `TransactionFormSheet`
  has a Category picker and a Subcategory picker filtered to that Category —
  changing or clearing the Category clears an incompatible Subcategory,
  mirroring `TransactionController.verifyCategoryAndSubcategory`'s server-side
  rule. `TransactionsViewModel` loads every Category's Subcategories up front
  (a small, owner-created list) rather than fetching per keystroke.

`PCCUI` has no automated tests beyond the pure-logic seams in
`Tests/PCCUITests` (`PCCHTTPTransportTests`, `SchoolBoardTests`,
`DeadlinesViewModelTests`, `WorkTreeTests` and friends) — see `Package.swift`'s
own comment on why the views themselves stay untested. It has been verified
with `swift build --target PCCUI` (type-checks and links) and exercised
through `PCCDesktop` below, but not run in a simulator or on-device.

### How the screens got here

This section is history, not a description of the package as it stands — the
types it names below were real at the time and several no longer exist. The
current entry points are the table above.

Screens landed one domain at a time: Projects and Tasks first, then the
read-only Deadlines screen, Personal Commitments and the merged Calendar
(ticket #7), the Automation Log (ticket #8), Clients (ticket #17), a Sprints
section inside a Project detail flow (ticket #18), Courses (ticket #19) with a
Task↔Course picker and a Course-scoped Tasks section (ticket #20), a Meetings
section listing a Course's linked Commitments (ticket #56), Time Entries
(ticket #27) and the live-timer control (ticket #28), the Work Hours rollup
(ticket #25), Accounts (ticket #36), Transactions (ticket #37), Categories with
a Subcategories section (ticket #39), Finances Reporting (ticket #40) and
Notifications (ticket #46).

Two structural passes then replaced most of that surface:

- **Issue #89** merged the Clients, Projects, Tasks, Time Entries and Work
  Hours screens into one `WorkView`. `ClientsView`, `ProjectsView`,
  `ProjectDetailView`, `TasksView`, `TimeEntriesView`, `TimerView` and
  `WorkHoursView`, along with `ClientsViewModel`, `ProjectsViewModel`,
  `TimeEntriesViewModel` and `WorkHoursViewModel`, were deleted; `WorkViewModel`
  owns the Client/Project/Sprint/Task/Time Entry CRUD they used to own between
  them, and `TimerViewModel` survived as an embedded control.
- **Issue #90** replaced the Courses screen with `SchoolView`. `CourseView`,
  `CourseDetailView` and `CoursesViewModel` were deleted, along with the
  `makeTasksViewModel(for:)`/`makeCommitmentsViewModel(for:)` factories that
  scoped a Tasks/Commitments view model to one Course: `SchoolViewModel` loads
  the flat lists once and derives each Course's slice locally through
  `SchoolBoard` instead of re-fetching per Course.

**Issue #98** finished the cleanup those two left behind. `TasksViewModel` and
its `TasksViewModelTests` were deleted rather than kept as unconsumed `public`
API: `WorkViewModel` had taken over every one of its CRUD methods, and its
`isOverdue(_:referenceDate:)` rule had no live caller — `DeadlinesViewModel`
owns the equivalent rule for the screen that actually renders overdue state.
`PersonalCommitmentsViewModel.scopedCourseID` went for the same reason: nothing
had passed it since #90, since `SchoolViewModel` filters the Commitments it
already loaded. This section, and the current-state one above it, were split
apart in the same pass — they had grown into each other, leaving the "how to
consume this package" text advertising twelve types that no longer existed.

The backend's `PCCTask` model and the client's `PCCTask` struct are named
`PCCTask` in Swift, not `Task` — that would shadow `_Concurrency.Task`
throughout their targets. Category (ticket #39) is named `PCCCategory` in
Swift on both sides for the same reason, but against a different collision:
an unqualified `Category` collides with the Objective-C runtime's own
`Category` typedef (`objc/runtime.h`, pulled in transitively through
Foundation on Darwin). In every case the domain term ("Task", "Category")
is what appears in the API paths/JSON and the UI text — only the Swift
symbol differs.

### Local dashboard preview (no Xcode)

`Sources/PCCDesktop` is a Mac client, separate from the real Mac/iOS app
targets described above — a plain `.executableTarget` (see Package.swift)
that composes every `PCCUI` screen into one `NavigationSplitView` window —
a sidebar listing every screen, with the selected one in the detail pane.
SwiftUI's `App` protocol works fine as a bare SPM executable against the
macOS SDK the Command Line Tools already ship, with no Xcode.app
installation required — it just can't run on the iOS Simulator (that
specifically needs `xcrun simctl`, part of full Xcode). It reads
`PCC_BASE_URL` (default `http://127.0.0.1:8080`) and `PCC_AUTH_TOKEN`
(default `mac-token`, must be one of the backend's `AUTH_TOKENS` values)
from the environment, falling back to those defaults when launched with no
environment at all — as happens double-clicking the `.app` bundle below.

It started as a dev-only preview for iterating on `PCCUI` without Xcode,
and per `docs/adr/0010` is now also promoted to the real daily-use Mac
client — see "Deployment (daily use on this Mac)" above for
`scripts/redeploy.sh`, which wraps this executable into a launchable
`/Applications/PCCDesktop.app`. The two loops below (running the raw
binary, or `dev-dashboard.sh`'s watch-and-relaunch) remain the fast local
iteration path for `PCCUI` changes; they're separate from — and don't
touch — the deployed `.app` bundle.

To view it with the backend running (`swift run App serve`, see "Local
setup" above), either run the binary directly:

```sh
swift build --product PCCDesktop && .build/debug/PCCDesktop
```

or use `scripts/dev-dashboard.sh`, which watches `Sources/PCCUI` and
`Sources/PCCDesktop` and rebuilds + relaunches the app window on every
save — not a true hot-swap (each change is a fresh process launch, so
in-window state resets), but a save-and-see-it loop of a few seconds with
nothing to install:

```sh
PCC_AUTH_TOKEN=mac-token ./scripts/dev-dashboard.sh
```
