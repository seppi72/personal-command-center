import Vapor

private struct CalDAVClientKey: StorageKey {
    typealias Value = any CalDAVClient
}

extension Application {
    /// The `CalDAVClient` used to push Personal Commitments to the external
    /// Calendar (ADR-0002). Tests inject a fake (`FakeCalDAVClient`) into
    /// this before calling `configure(_:)`; `configure(_:)` only installs
    /// the real `ICloudCalDAVClient` when nothing has been injected yet, so
    /// tests never touch a live iCloud account (spec #1's testing seam).
    var calDAVClient: any CalDAVClient {
        get {
            guard let client = self.storage[CalDAVClientKey.self] else {
                fatalError("Application.calDAVClient accessed before configure(_:) installed one")
            }
            return client
        }
        set {
            self.storage[CalDAVClientKey.self] = newValue
        }
    }

    /// Whether a `CalDAVClient` has already been installed — `configure(_:)`
    /// checks this so it doesn't overwrite a test's injected fake.
    var hasCalDAVClient: Bool {
        self.storage.contains(CalDAVClientKey.self)
    }
}
