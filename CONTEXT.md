# Personal Command Center

A single-user system that aggregates, organizes, prioritizes, and surfaces the owner's life data (tasks, projects, finances, calendar, school, work, and more) with minimal manual entry. For domains that already have an external system of record, the Command Center mirrors and surfaces that data rather than owning it; for domains with no existing authority, the Command Center is itself the canonical store.

## Language

**Task**:
The atomic unit of work. May belong to a Project or a Course, not both — the two are alternate containers of the same kind, not orthogonal tags — and may carry a Deadline.
_Avoid_: To-do, item, action.

**Project**:
A container of related Tasks with its own lifecycle, distinct from any single Task. May optionally belong to a Client, and may optionally be broken into Sprints.

**Sprint**:
A time-boxed iteration within one Project that Tasks can be grouped into. A Project's use of Sprints is optional, but a Sprint itself is scoped to the Project it was created in for its lifetime — it doesn't move to a different Project.

**Client**:
A grouping of Projects (e.g. an employer or a freelance client) — the owner may have one or many. Sits above Project, not beside it: Client → Project → (optional Sprint) → Task. Created directly by the owner, not auto-detected — there's no external source of "you have a new client."

**Deadline**:
A due-date concept attachable to a Task, Project, Course, or other dated obligation.

**Personal Commitment**:
A recurring or scheduled personal obligation (e.g. a standing calendar block), distinct from a Task — it is scheduled/time-bound rather than completed.

**Automation Log**:
An audit-trail record of an action the system took on its own (e.g. a data pull, an auto-generated entity), kept so the automation can be trusted and debugged rather than re-checked by hand.

**Notification**:
A surfaced item requiring the owner's attention. Has two aspects: membership in the "needs you" queue (the data) and delivery through a push/alert channel (the transport).

**Time Entry**:
A record spanning a start and end time, captured primarily by starting/stopping a live timer, with after-the-fact manual entry (the same start/end shape, just typed in) as a fallback. Attaches to exactly one of Task, Project, Client, or Course — required, never none, never more than one — the same alternate-container shape as Task's own Project/Course exclusivity (ADR-0003), extended to a fourth peer (ADR-0004). A direct Project, Client, or Course attachment is for work that isn't task-shaped (e.g. a call, admin time, sitting in a lecture). Is how Work Hours is tracked, since no external timesheet system exists to mirror.
_Avoid_: Timesheet entry, log entry.

**Work Hours**:
The aggregate view over Time Entries — totals grouped by day, or by one of Time Entry's four containers (Task, Project, Client, Course), over a chosen range. A Project/Client/Course total folds in not just Time Entries logged directly against that container but, transitively, everything logged beneath it: a Project's total includes its Tasks' entries, a Client's total includes its Projects' totals (direct and Task-level), a Course's total includes its Tasks' entries (ADR-0005). A Task total is direct entries only — a Task has nothing below it to fold in. A running live timer (no `endDate` yet) doesn't contribute to any Work Hours total until it's stopped.

**Course**:
A container of related Tasks/Deadlines for a single school class (e.g. "CS 301"), analogous to how a Project contains personal Tasks — down to optionally carrying its own Deadline the same way a Project can. Created directly by the owner each term, not auto-detected; the Tasks/Deadlines inside it are what auto-populate, from a school data source.

**Term**:
The month and year identifying which academic term a Course belongs to (e.g. "September 2026").

**Source of truth (per domain)**:
Whether the Command Center is canonical owner of a domain's data or a mirror of an external system of record.
- **Canonical** (Command Center owns it): Tasks, Projects, Deadlines, Personal Commitments, Work Hours (self-logged — no employer timesheet system exists to mirror).
- **Mirrored** (an external system remains authoritative): Finances, Calendar, School.
