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

    /// Issues a CalDAV `calendar-query` `REPORT` against the configured
    /// calendar collection, asking for every `VEVENT`'s raw `.ics` data,
    /// then hand-parses the multistatus XML response and each event's
    /// iCalendar body — ADR-0002 accepted "hand-rolling event
    /// serialization/parsing" as CalDAV's trade-off against EventKit.
    /// Matches `upsertEvent`/`deleteEvent`'s own minimal, non-RFC-exhaustive
    /// style: it reads `UID`/`SUMMARY`/`DTSTART`/`DTEND`/`RRULE` off each
    /// `VEVENT` and skips anything malformed rather than failing the whole
    /// pull over one bad event.
    func fetchEvents() async throws -> [CalDAVEvent] {
        var request = URLRequest(url: calendarURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(username):\(appSpecificPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(Self.calendarQueryBody.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CalDAVClientError.serverError(status: status)
        }
        return Self.parseEvents(fromMultistatus: data)
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

    /// The inverse of `escaped(_:)`, applied when reading a `SUMMARY` back
    /// out of a pulled event. Order matters: unescape `\\` last, or an
    /// already-unescaped `\,`/`\;`/`\n` produced by an earlier step would
    /// get its backslash stripped a second time.
    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// A minimal `calendar-query` `REPORT` body asking for every `VEVENT`'s
    /// raw `.ics` data on the configured collection — no time-range filter,
    /// since spec #1 doesn't call for windowing the pull.
    private static let calendarQueryBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop>
            <C:calendar-data/>
          </D:prop>
          <C:filter>
            <C:comp-filter name="VCALENDAR">
              <C:comp-filter name="VEVENT"/>
            </C:comp-filter>
          </C:filter>
        </C:calendar-query>
        """

    /// Extracts every `<calendar-data>` element's text (each one a full
    /// `.ics` document for one calendar resource) out of the multistatus
    /// XML `REPORT` response, then hands each off to `parseVEvents`.
    private static func parseEvents(fromMultistatus data: Data) -> [CalDAVEvent] {
        let delegate = CalendarDataXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.calendarDataBlocks.flatMap(parseVEvents)
    }

    /// Hand-parses one `.ics` document's `VEVENT` block(s) — RFC 5545 line
    /// unfolding (a continuation line starts with a space or tab), then a
    /// plain `NAME[;PARAM=...]:VALUE` split per line, matching the same
    /// property names `iCalendar(for:)` writes. A `VEVENT` missing any of
    /// `UID`/`SUMMARY`/`DTSTART`/`DTEND`, or with a `DTSTART`/`DTEND` this
    /// parser can't read, is skipped rather than failing the whole pull.
    private static func parseVEvents(fromICalendar text: String) -> [CalDAVEvent] {
        let unfolded = text
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        let lines = unfolded.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        var events: [CalDAVEvent] = []
        var current: [String: String] = [:]
        var isInsideEvent = false

        for line in lines {
            if line == "BEGIN:VEVENT" {
                isInsideEvent = true
                current = [:]
                continue
            }
            if line == "END:VEVENT" {
                isInsideEvent = false
                if let event = makeEvent(from: current) {
                    events.append(event)
                }
                continue
            }
            guard isInsideEvent, let colonIndex = line.firstIndex(of: ":") else { continue }
            // Strip a `;VALUE=DATE`-style parameter off the property name
            // so e.g. `DTSTART;VALUE=DATE` is still keyed as `DTSTART`.
            let name = line[line.startIndex..<colonIndex].split(separator: ";").first.map(String.init) ?? ""
            let value = String(line[line.index(after: colonIndex)...])
            current[name] = value
        }
        return events
    }

    private static func makeEvent(from fields: [String: String]) -> CalDAVEvent? {
        guard let uid = fields["UID"],
            let title = fields["SUMMARY"],
            let startString = fields["DTSTART"], let start = parsedDate(startString),
            let endString = fields["DTEND"], let end = parsedDate(endString)
        else {
            return nil
        }
        return CalDAVEvent(uid: uid, title: unescaped(title), start: start, end: end, recurrenceRule: fields["RRULE"])
    }

    /// Accepts both the `DTSTART`/`DTEND` shape `iCalendar(for:)` writes
    /// (`yyyyMMdd'T'HHmmss'Z'`) and the all-day, time-less shape
    /// (`yyyyMMdd`, used with `;VALUE=DATE`) a real external Calendar can
    /// send back.
    private static func parsedDate(_ value: String) -> Date? {
        dateStamp.date(from: value) ?? dateOnlyStamp.date(from: value)
    }

    private static let dateStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dateOnlyStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// Collects the text content of every `<calendar-data>` element (any
/// namespace prefix — `XMLParser` reports each element's raw qualified
/// name, e.g. `C:calendar-data`, when namespace processing is off, which is
/// `XMLParser`'s default) in a CalDAV multistatus `REPORT` response.
private final class CalendarDataXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var calendarDataBlocks: [String] = []
    private var isInsideCalendarData = false
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName.hasSuffix("calendar-data") {
            isInsideCalendarData = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideCalendarData {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.hasSuffix("calendar-data") {
            calendarDataBlocks.append(currentText)
            isInsideCalendarData = false
        }
    }
}
