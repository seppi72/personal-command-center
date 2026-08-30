---
status: accepted
---

# LaunchAgent Mac deployment, `PCCDesktop` promoted to daily client

No Xcode is installed on the deployment machine (only the Command Line Tools), so the real Mac/iOS app targets `ADR-0001` anticipated can't be built yet, and today's need is narrower than that ADR's scope anyway: use on this Mac only, not cross-device sync. Rather than wait for Xcode or stand up a cloud host, we deploy `App` as a release-build `launchd` LaunchAgent (auto-starts at login, restarts on crash) bound to `127.0.0.1` only, and promote `PCCDesktop` — until now explicitly documented as a dev-only preview with no app icon — to the real daily-use client, packaged as a hand-built (unsigned, non-Xcode) `.app` bundle in `/Applications`.

This is a deliberate interim state, not a replacement for `ADR-0001`'s eventual real app targets: `PCCDesktop`'s promotion should be revisited (and its own doc comments' "dev-only" framing corrected) once a real Xcode-built client exists, and the `127.0.0.1`-only binding should be revisited the day an iOS client is actually being built and needs LAN reachability.
