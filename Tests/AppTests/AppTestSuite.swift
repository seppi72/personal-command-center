import Testing

/// Every suite in this target exercises the same real (test) Postgres
/// database, with no per-test isolation (see each suite's own doc comment).
/// swift-testing runs suites in parallel with each other by default, and a
/// suite's own `.serialized` trait only serializes *within* that suite — it
/// doesn't stop it from racing a different suite. Nesting every suite here,
/// under one `.serialized` parent, is what stops e.g. `ProjectTests`,
/// `TaskTests`, `DeadlineTests`, and `ClientTests` (which share the
/// `projects`, `tasks`, and/or `clients` tables) from running concurrently
/// and corrupting each other's rows. `PersonalCommitmentTests` owns its own
/// tables and doesn't share them with any other suite, but is nested here
/// too for one consistent top-level ordering rather than a special case.
@Suite(.serialized)
struct AppTestSuite {}
