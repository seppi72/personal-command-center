# Personal Command Center

A single-user system that aggregates, organizes, prioritizes, and surfaces the owner's life data (tasks, projects, finances, calendar, school, work, and more) with minimal manual entry. For domains that already have an external system of record, the Command Center mirrors and surfaces that data rather than owning it; for domains with no existing authority, the Command Center is itself the canonical store.

## Language

**Task**:
The atomic unit of work. May belong to a Project, and may carry a Deadline.
_Avoid_: To-do, item, action.

**Project**:
A container of related Tasks with its own lifecycle, distinct from any single Task. May optionally belong to a Client, and may optionally be broken into Sprints.

**Sprint**:
An optional time-boxed iteration within a Project that Tasks can be grouped into.

**Client**:
A grouping of Projects (e.g. an employer or a freelance client) — the owner may have one or many. Sits above Project, not beside it: Client → Project → (optional Sprint) → Task. Created directly by the owner, not auto-detected — there's no external source of "you have a new client."

**Deadline**:
A due-date concept attachable to a Task, Project, or other dated obligation.

**Personal Commitment**:
A recurring or scheduled personal obligation (e.g. a standing calendar block), distinct from a Task — it is scheduled/time-bound rather than completed.

**Automation Log**:
An audit-trail record of an action the system took on its own (e.g. a data pull, an auto-generated entity), kept so the automation can be trusted and debugged rather than re-checked by hand.

**Notification**:
A surfaced item requiring the owner's attention. Has two aspects: membership in the "needs you" queue (the data) and delivery through a push/alert channel (the transport).

**Time Entry**:
A record of duration spent on work, captured primarily by starting/stopping a live timer, with after-the-fact manual duration entry as a fallback. Attaches to a Task, or directly to a Project or Client when the work isn't task-shaped (e.g. a call, admin time). Is how Work Hours is tracked, since no external timesheet system exists to mirror.

**Course**:
A container of related Tasks/Deadlines for a single school class (e.g. "CS 301"), analogous to how a Project contains personal Tasks. Created directly by the owner each term, not auto-detected; the Tasks/Deadlines inside it are what auto-populate, from a school data source.

**Source of truth (per domain)**:
Whether the Command Center is canonical owner of a domain's data or a mirror of an external system of record.
- **Canonical** (Command Center owns it): Tasks, Projects, Deadlines, Personal Commitments, Work Hours (self-logged — no employer timesheet system exists to mirror).
- **Mirrored** (an external system remains authoritative): Finances, Calendar, School.
