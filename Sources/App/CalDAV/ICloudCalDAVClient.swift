import Foundation

/// The real `CalDAVClient`: pushes to one specific iCloud CalDAV calendar
/// collection (ADR-0002), authenticated with Basic Auth using an
/// app-specific password.
///
/// This client does **not** perform CalDAV principal/calendar-home
/// discovery — the multi-step `PROPFIND` dance against
/// `https://caldav.icloud.com` that resolves a username into that
/// account's actual calendar collection URL (e.g.
/// `https://p12-caldav.icloud.com/12345678/calendars/home/`). That URL is a
/// one-time manual lookup (documented in the README) supplied as
/// configuration, not re-derived by the server on every request — a
/// deliberate scope cut to keep this client to plain event PUT/DELETE, the
/// only CalDAV operations ticket #6 needs.
struct ICloudCalDAVClient: CalDAVClient {
    let calendarURL: URL
    let username: String
    let appSpecificPassword: String
    let session: URLSession

    init(calendarURL: URL, username: String, appSpecificPassword: String, session: URLSession = .shared) {
        self.calendarURL = calendarURL
        self.username = username
        self.appSpecificPassword = appSpecificPassword
        self.session = session
    }

    func upsertEvent(_ event: CalDAVEvent) async throws {
        var request = makeRequest(uid: event.uid, method: "PUT")
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.iCalendar(for: event).utf8)
        try await send(request)
    }

    func deleteEvent(uid: String) async throws {
        try await send(makeRequest(uid: uid, method: "DELETE"))
    }

    private func makeRequest(uid: String, method: String) -> URLRequest {
        var request = URLRequest(url: calendarURL.appendingPathComponent("\(uid).ics"))
        request.httpMethod = method
        let credentials = Data("\(username):\(appSpecificPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CalDAVClientError.serverError(status: status)
        }
    }

    /// A minimal RFC 5545 `VEVENT` — a title, start/end, and an optional raw
    /// `RRULE` line passed through as-is (the caller's recurrence rule isn't
    /// validated here, only forwarded).
    private static func iCalendar(for event: CalDAVEvent) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Personal Command Center//EN",
            "BEGIN:VEVENT",
            "UID:\(event.uid)",
            "DTSTAMP:\(dateStamp.string(from: Date()))",
            "DTSTART:\(dateStamp.string(from: event.start))",
            "DTEND:\(dateStamp.string(from: event.end))",
            "SUMMARY:\(escaped(event.title))",
        ]
        if let recurrenceRule = event.recurrenceRule {
            lines.append("RRULE:\(recurrenceRule)")
        }
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        // RFC 5545 requires CRLF line endings.
        return lines.joined(separator: "\r\n")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static let dateStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
