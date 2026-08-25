# A Task belongs to a Project or a Course, never both

Course was added as a container parallel to Project — `CONTEXT.md` describes it as "analogous to how a Project contains personal Tasks." The alternative was to let Project and Course act as independent, orthogonal references on Task (like Project and Sprint today), so a Task could in principle carry both at once.

We chose exclusivity: a Task references at most one of `projectID`/`courseID`, enforced at assignment time — setting one clears the other (`PUT /v1/tasks/:taskID/project` and the equivalent Course endpoint both accept `null` to remove, the same shape the existing Project-removal endpoint already has). Project-shaped work and school-shaped work are different life areas for the owner, and nothing in the domain gives meaning to a Task that's simultaneously "in Project X" and "in Course Y." Modeling them as alternate containers of the same kind — rather than independent tags — keeps that meaningless state unrepresentable instead of merely unused.

The trade-off: if a future need ever wants a Task tagged with both (e.g. a school project that's also tracked as freelance Client work), this boundary has to be revisited and the exclusivity relaxed — a real but currently hypothetical cost against a concrete, present ambiguity avoided.
