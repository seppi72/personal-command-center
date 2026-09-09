# Personal Command Center

A single-user system that aggregates, organizes, prioritizes, and surfaces the owner's life data (tasks, projects, finances, calendar, school, work, and more) with minimal manual entry. For domains that already have an external system of record, the Command Center mirrors and surfaces that data rather than owning it; for domains with no existing authority, the Command Center is itself the canonical store.

## Language

**Task**:
The atomic unit of work — something the owner *completes*, as distinct from a Personal Commitment, which is something the owner *attends*. Belongs to a Project or directly to a Course, not both — the two are alternate containers of the same kind, not orthogonal tags (ADR-0003) — and may carry a Deadline. Since a Project may itself belong to a Course (ADR-0011), a Task can reach a Course either directly or through its Project; it still has exactly one container.
_Avoid_: To-do, item, action.

**Kind**:
An optional label on a Task naming what sort of work it is — homework, study, reading, and the like. Purely for filtering and display; it carries no behaviour and doesn't affect which container a Task belongs to. An exam or a quiz is deliberately *not* a Kind, because those are attended at a fixed time rather than completed — they're Personal Commitments.

**Project**:
A container of related Tasks with its own lifecycle, distinct from any single Task. May optionally belong to a Client or to a Course — not both, and not necessarily either (ADR-0011): a Project is billable work for a Client or coursework for a Course. May optionally be broken into Sprints regardless of which parent it has.

**Sprint**:
A time-boxed iteration within one Project that Tasks can be grouped into. A Project's use of Sprints is optional, but a Sprint itself is scoped to the Project it was created in for its lifetime — it doesn't move to a different Project.

**Client**:
A grouping of Projects (e.g. an employer or a freelance client) — the owner may have one or many. Sits above Project, not beside it: Client → Project → (optional Sprint) → Task. Created directly by the owner, not auto-detected — there's no external source of "you have a new client."

**Deadline**:
A due-date concept attachable to a Task, Project, Course, or other dated obligation.

**Personal Commitment**:
A recurring or scheduled personal obligation (e.g. a standing calendar block), distinct from a Task — it is scheduled/time-bound rather than completed. School exams and quizzes are Personal Commitments for this reason: they are attended at a fixed time, not ticked off. May optionally attach to a Course (e.g. a recurring class meeting time) — a single optional link, not the four-way container exclusivity Time Entry has (ADR-0004); a Course can't be deleted while a Personal Commitment still references it, the same referential guard Time Entry's own containers and Finances' Accounts already have (`docs/adr/0009-manual-entry-not-lms-integration-for-school.md`). **Meeting** is this term's school-side display name, and only that: on the School screen, a Personal Commitment attached to a Course is labelled a Meeting, because "Personal Commitment" reads wrong for a lecture, lab, exam or quiz. It is not a separate concept — there is no Meeting model, endpoint, or field, and outside a Course context the term is always Personal Commitment.

**Automation Log**:
An audit-trail record of an action the system took on its own (e.g. a data pull, an auto-generated entity), kept so the automation can be trusted and debugged rather than re-checked by hand.

**Notification**:
A surfaced item requiring the owner's attention, stored rather than live-computed so it can be dismissed and stay dismissed — unlike, e.g., Deadline's proximity-sorted view or Net Worth, which are recomputed fresh on every request with nothing persisted. Has two aspects: membership in the "needs you" queue (a `Notification` row pointing back at whatever triggered it via `sourceType`/`sourceID`, the same open-ended pointer shape Automation Log already uses for its own `subjectType`/`subjectID`) and delivery through a push/alert channel (the transport) — for v1 the transport is in-app surfacing only, not an OS-level push notification (`docs/adr/0008-in-app-notifications-over-push-for-v1.md`). Sourced from two places in v1: a Task/Project/Course crossing overdue (created and auto-cleared by a recurring scan, the same recurring-job shape as Calendar's own sync schedule) and an Automation Log entry logged with outcome `.failure` (created inline at the point of failure — additive to Automation Log's own existing live "most recent failure" banner, not a replacement for it). At most one open Notification exists per overdue source item at a time — dismissing it holds until the underlying condition actually changes (resolved, or a fresh Automation Log failure occurs); there's no separate read/unread state, just dismissed or not.

**Time Entry**:
A record spanning a start and end time, captured primarily by starting/stopping a live timer, with after-the-fact manual entry (the same start/end shape, just typed in) as a fallback. Attaches to exactly one of Task, Project, Client, or Course — required, never none, never more than one — the same alternate-container shape as Task's own Project/Course exclusivity (ADR-0003), extended to a fourth peer (ADR-0004). A direct Project, Client, or Course attachment is for work that isn't task-shaped (e.g. a call, admin time, sitting in a lecture). Is how Work Hours is tracked, since no external timesheet system exists to mirror. At most one Time Entry is running (no `endDate` yet) at a time — starting a new live timer requires stopping or cancelling whichever one is already running; there's no concurrent-timer concept in this domain.
_Avoid_: Timesheet entry, log entry.

**Work Hours**:
The aggregate view over Time Entries — totals grouped by day, or by one of Time Entry's four containers (Task, Project, Client, Course), over a chosen range. A Project/Client/Course total folds in not just Time Entries logged directly against that container but, transitively, everything logged beneath it: a Project's total includes its Tasks' entries, a Client's total includes its Projects' totals (direct and Task-level), a Course's total includes both its own Tasks' entries and its Projects' totals (ADR-0005, extended by ADR-0011). A Task total is direct entries only — a Task has nothing below it to fold in. A running live timer (no `endDate` yet) doesn't contribute to any Work Hours total until it's stopped.

**Course**:
A container of related Tasks/Deadlines for a single school class (e.g. "CS 301"), analogous to how a Project contains personal Tasks — and, like a Client, it may also contain Projects of its own for coursework that has the Project shape, such as a semester group assignment (ADR-0011) — down to optionally carrying its own Deadline the same way a Project can. Belongs to exactly one Term — required, never none. Carries the Units it weighs and, once the school issues one, its final Grade. Created directly by the owner each Term, not auto-detected; its Tasks, Deadlines, Time Entries, and Personal Commitments are entered the same way any other Task, Deadline, Time Entry, or Personal Commitment is — there's no accessible school data source to auto-populate them from, a deliberate decision, not a placeholder for a future sync (`docs/adr/0009-manual-entry-not-lms-integration-for-school.md`).

**Grade**:
The single final mark a Course carries, entered by the owner rather than computed from logged assignment scores — the school is the authority on a subject's grade and this app mirrors it (`docs/adr/0013-owner-entered-course-grade-over-computed-gradebook.md`). There is no gradebook, no per-assignment score, and no weighting of homework against exams. Empty means the subject is ongoing. Legal values are a discrete ladder rather than free numeric entry — `1.00`, `1.25`, `1.50`, `1.75`, `2.00`, `2.25`, `2.50`, `2.75`, `3.00`, and `5.00` (failure) — on which **lower is better** and `3.00` is the passing mark, the only figure in this system that runs that direction. Two non-numeric marks share the field: **DRP** (dropped) is terminal, the subject is over and counts toward nothing; **INC** (incomplete) is not, and the subject still reads as ongoing until the mark is replaced with a real one. A retaken subject leaves both attempts in place and both count, matching what a transcript shows — there is no link between an original and a retake.
_Avoid_: GPA, letter grade, mark (on its own).

**Units**:
How much a Course weighs in General Weighted Average — required on every Course, since a unitless Course would silently corrupt both figures computed over it. Decimal rather than integer, so half-unit subjects stay expressible.
_Avoid_: Credits, credit hours.

**General Weighted Average**:
The owner's academic standing — the sum of (Grade × Units) divided by the sum of Units, over the subjects whose Grade counts toward it. Computed fresh on every request and never stored, the same shape as Net Worth and Work Hours, so it can't drift from the Grades underneath it. Surfaced both for the current Term and cumulatively; the cumulative figure is unit-weighted across every subject in every Term, **not** an average of the per-Term figures, since averaging averages overweights a light semester. A `5.00` counts toward it — a failure is a real Grade and should drag the average down — while `INC`, `DRP`, and an ungraded ongoing subject count toward nothing.
_Avoid_: GPA, average grade.

**Units Earned**:
The sum of Units over passed subjects, always cumulative across every Term. Distinct from General Weighted Average and deliberately not the same filter: a failed subject's `5.00` still weighs in the average but earns nothing toward graduation, because the two figures answer different questions. `INC` and `DRP` earn nothing either.
_Avoid_: Credits earned.

**Term**:
One academic term at the owner's school — a semester, since the school runs on semestral terms. Identified by its **year** plus its **Semester** (1st Semester, 2nd Semester, or Summer), unique on that pair: a semester never crosses a year boundary at this school, so the pair is unambiguous and no school-year span ("2026-2027") is needed. Its display name (e.g. "1st Semester 2026") is *derived* from those two, never free text — free text would let "1st Sem 2026" and "First Semester 2026" exist as separate Terms with Courses split between them, quietly breaking every per-Term figure. Optionally carries the **start and end dates** the school publishes in its academic calendar; the two are set together or not at all, and two Terms' date ranges may not overlap, since overlapping ranges would give "which semester is happening now" two answers. A Term with no dates set is never treated as the current one — "not set yet" reads honestly rather than as a claim about today. An entity rather than a label on a Course, and deliberately so: a Term has attributes of its own (`docs/adr/0012-term-is-an-entity.md`). A Term can't be deleted while any Course still belongs to it — the same referential guard Course has for its Personal Commitments, Time Entries and Projects, and Account has for its Transactions; cascading would silently delete a semester of academic history.
_Avoid_: Semester (on its own — a Semester is which of the three a Term is, not the Term itself), school year.

**Account**:
A named store of money the owner tracks — Checking, Savings, Cash, Credit Card, Investment, or Loan — created directly by the owner, not auto-detected (Finances is canonical; see "Source of truth" below, and `docs/adr/0006-manual-entry-over-bank-aggregation-for-finances.md`). An Account's Type classifies it as an asset (Checking, Savings, Cash, Investment) or a liability (Credit Card, Loan) for Net Worth purposes. Its Balance is computed as its `openingBalance` (set once at creation) plus the signed sum of every Transaction logged against it — never edited directly (`docs/adr/0007-computed-balance-over-reconciliation.md`).

**Transaction**:
A single logged movement of money against exactly one Account, signed as an expense (money out) or income (money in). May optionally carry a Category or a Subcategory, but neither is required.
_Avoid_: Entry, log entry (already claimed by Time Entry's own avoid-list).

**Category** / **Subcategory**:
An owner-created label for grouping Transactions by kind of spending (e.g. "Food"), created directly by the owner — the same "no external source to auto-detect from" shape as Client/Course. A Category may contain Subcategories (e.g. "Groceries", "Takeout", "Cafe", "Drinks" under "Food") — exactly one level deep; a Subcategory doesn't itself have children. A Subcategory is scoped to the Category it was created in for its lifetime, the same way a Sprint is scoped to its Project. A Transaction tagged with a Subcategory transitively counts toward its parent Category too.

**Net Worth**:
The owner's total financial position at a point in time — the sum of every asset Account's Balance minus the sum of every liability Account's Balance. Computed live from current Balances, not stored; surfaced both as a current figure and as a trend over time.

**Projected Balance**:
The forecasted value of an Account's Balance at the end of the current week or month, computed by extrapolating the trailing 30-day average daily net cash flow (income minus expenses) forward across the period's remaining days. Distinct from Net Worth — it projects one Account forward, not the owner's total position.

**Source of truth (per domain)**:
Whether the Command Center is canonical owner of a domain's data or a mirror of an external system of record.
- **Canonical** (Command Center owns it): Tasks, Projects, Deadlines, Personal Commitments, Work Hours (self-logged — no employer timesheet system exists to mirror), Finances (self-logged — the owner holds a mix of digital and traditional banks with no single aggregatable external source, so this mirrors Work Hours' shape rather than Calendar's), School (self-logged — no accessible school data source exists to pull from, so a Course's Tasks, Deadlines, Time Entries, and Personal Commitments are entered the same way any other Task, Deadline, Time Entry, or Personal Commitment is; `docs/adr/0009-manual-entry-not-lms-integration-for-school.md`), Notifications (self-generated by the Command Center from its own other domains — there's no external source to mirror a "needs you" queue from).
- **Mirrored** (an external system remains authoritative): Calendar.
