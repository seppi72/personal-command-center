import Foundation
import Testing

@testable import PCCUI

/// Covers `PCCHTTPTransport` (ticket #54) — the shared transport every
/// `PCCUI` API client composes. Request construction, encoding, and status
/// validation are tested directly as pure logic; `send`/`sendExpectingNoBody`
/// (the two methods that actually perform I/O) are tested against
/// `StubURLProtocol` rather than a running backend. `.serialized` because
/// every test in this suite drives `StubURLProtocol`'s single shared
/// handler.
@Suite("PCCHTTPTransport", .serialized)
struct PCCHTTPTransportTests {
    private let baseURL = URL(string: "https://example.test")!

    private func makeTransport(handler: (@Sendable (URLRequest) -> (Int, Data))? = nil) -> PCCHTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = handler
        return PCCHTTPTransport(baseURL: baseURL, bearerToken: "test-token", session: URLSession(configuration: configuration))
    }

    // MARK: - makeRequest

    @Test("builds a plain request with bearer auth and no query string")
    func makeRequestPlain() throws {
        let transport = makeTransport()
        let request = try transport.makeRequest(path: "v1/widgets", method: "GET")
        #expect(request.url == baseURL.appendingPathComponent("v1/widgets"))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.url?.query == nil)
    }

    @Test("encodes uuid, date, and string query values, dropping nil")
    func makeRequestQuery() throws {
        let transport = makeTransport()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let request = try transport.makeRequest(
            path: "v1/widgets",
            method: "GET",
            query: ["id": .uuid(id), "since": .date(date), "label": .string("x"), "omitted": nil]
        )
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(byName["id"] == id.uuidString)
        #expect(byName["since"] == ISO8601DateFormatter().string(from: date))
        #expect(byName["label"] == "x")
        #expect(byName["omitted"] == nil)
        #expect(byName.count == 3)
    }

    @Test("an all-nil query behaves the same as no query at all")
    func makeRequestAllNilQuery() throws {
        let transport = makeTransport()
        let request = try transport.makeRequest(path: "v1/widgets", method: "GET", query: ["id": nil])
        #expect(request.url?.query == nil)
    }

    // MARK: - attach

    @Test("attaches a JSON body with iso8601 dates and sets Content-Type")
    func attachEncodesBody() throws {
        let transport = makeTransport()
        var request = URLRequest(url: baseURL)
        struct Payload: Encodable { let name: String; let when: Date }
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try transport.attach(Payload(name: "widget", when: when), to: &request)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["name"] as? String == "widget")
        #expect(decoded?["when"] as? String == ISO8601DateFormatter().string(from: when))
    }

    // MARK: - checkStatus

    private enum TestError: Error, Equatable {
        case unexpected
        case server(Int)
    }

    @Test("passes for every 2xx status")
    func checkStatusSuccess() throws {
        let transport = makeTransport()
        for code in [200, 201, 204, 299] {
            let response = try #require(HTTPURLResponse(url: baseURL, statusCode: code, httpVersion: nil, headerFields: nil))
            try transport.checkStatus(response, unexpectedResponse: TestError.unexpected, serverError: TestError.server)
        }
    }

    @Test("throws serverError for a non-2xx status, carrying the status code")
    func checkStatusServerError() throws {
        let transport = makeTransport()
        let response = try #require(HTTPURLResponse(url: baseURL, statusCode: 404, httpVersion: nil, headerFields: nil))
        #expect(throws: TestError.server(404)) {
            try transport.checkStatus(response, unexpectedResponse: TestError.unexpected, serverError: TestError.server)
        }
    }

    @Test("throws unexpectedResponse when the response isn't an HTTPURLResponse")
    func checkStatusUnexpectedResponse() throws {
        let transport = makeTransport()
        let response = URLResponse(url: baseURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(throws: TestError.unexpected) {
            try transport.checkStatus(response, unexpectedResponse: TestError.unexpected, serverError: TestError.server)
        }
    }

    // MARK: - send / sendExpectingNoBody (network round trip via StubURLProtocol)

    private struct Widget: Codable, Equatable {
        let id: UUID
        let updatedAt: Date
    }

    @Test("send decodes a successful response body")
    func sendDecodesSuccess() async throws {
        let id = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let body = try JSONEncoder.iso8601.encode(Widget(id: id, updatedAt: updatedAt))
        let transport = makeTransport { _ in (200, body) }
        let request = try transport.makeRequest(path: "v1/widgets", method: "GET")
        let widget: Widget = try await transport.send(
            request,
            unexpectedResponse: TestError.unexpected,
            serverError: TestError.server
        )
        #expect(widget == Widget(id: id, updatedAt: updatedAt))
    }

    @Test("send throws serverError for a failing response, without attempting to decode")
    func sendServerError() async throws {
        let transport = makeTransport { _ in (500, Data("not json".utf8)) }
        let request = try transport.makeRequest(path: "v1/widgets", method: "GET")
        await #expect(throws: TestError.server(500)) {
            let _: Widget = try await transport.send(
                request,
                unexpectedResponse: TestError.unexpected,
                serverError: TestError.server
            )
        }
    }

    @Test("sendExpectingNoBody succeeds on a successful status without decoding")
    func sendExpectingNoBodySuccess() async throws {
        let transport = makeTransport { _ in (204, Data()) }
        let request = try transport.makeRequest(path: "v1/widgets/1", method: "DELETE")
        try await transport.sendExpectingNoBody(request, unexpectedResponse: TestError.unexpected, serverError: TestError.server)
    }

    @Test("sendExpectingNoBody throws serverError for a failing response")
    func sendExpectingNoBodyServerError() async throws {
        let transport = makeTransport { _ in (409, Data()) }
        let request = try transport.makeRequest(path: "v1/widgets/1", method: "DELETE")
        await #expect(throws: TestError.server(409)) {
            try await transport.sendExpectingNoBody(request, unexpectedResponse: TestError.unexpected, serverError: TestError.server)
        }
    }
}

extension JSONEncoder {
    fileprivate static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Intercepts every request on sessions configured with it and answers with
/// whatever `handler` returns, rather than touching the network. `.serialized`
/// on the suite is what makes the single shared `handler` safe to reassign
/// per test.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
