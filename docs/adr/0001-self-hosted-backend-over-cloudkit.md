---
status: accepted
---

# Self-hosted backend, not CloudKit-only, for cross-device sync

The Command Center ships a Mac app and an iOS app that must share one canonical dataset (Tasks, Projects, Deadlines, Personal Commitments, Time Entries, etc.), and the system must also run scheduled automation — pulling Finances, Calendar, School, and other mirrored sources — independent of whether either app is open. CloudKit would have covered device sync with no server to run or maintain, but it can't host that always-on ingestion/polling logic. We chose a self-hosted or cloud backend (server + database) that both apps act as clients of, making it the natural home for automation as well as sync, at the cost of infrastructure we now have to build and operate ourselves.
