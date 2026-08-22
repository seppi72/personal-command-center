import Testing

/// Every suite in this target exercises the same real (test) Postgres
/// database, with no per-test isolation (see each suite's own doc comment).
/// swift-testing runs suites in parallel with each other by default, and a
/// suite's own `.serialized` trait only serializes *within* that suite — it
/// doesn't stop it from racing a different suite. Nesting every suite here,
/// under one `.serialized` parent, is what stops e.g. `ProjectTests`,
/// `TaskTests`, and `DeadlineTests` (which all share the `projects` and/or
/// `tasks` tables) from running concurrently and corrupting each other's
/// rows.
@Suite(.serialized)
struct AppTestSuite {}
