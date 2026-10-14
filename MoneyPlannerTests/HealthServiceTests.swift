import Foundation
import Synchronization
import Testing
@testable import MoneyPlanner

@Suite("HealthService — GET /healthz")
struct HealthServiceTests {
    @Test func buildsHealthRequestAndMapsOkStatus() async throws {
        let (baseURL, session) = StubURLProtocol.register(
            .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"status":"ok"}"#.utf8))
        )
        let service = HealthService(client: URLSessionHTTPClient(baseURL: baseURL, session: session))

        let health = try await service.fetchHealth()

        #expect(health == .available)
        let requests = StubURLProtocol.requests(for: baseURL)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/healthz")
        #expect(request.url?.query() == nil)
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func otherStatusIsDegraded() async throws {
        let (baseURL, session) = StubURLProtocol.register(
            .response(status: 200, body: Data(#"{"status":"starting"}"#.utf8))
        )
        let service = HealthService(client: URLSessionHTTPClient(baseURL: baseURL, session: session))

        #expect(try await service.fetchHealth() == .degraded)
    }

    @Test func baseURLWithPathPrefixIsPreserved() async throws {
        let (stubBaseURL, session) = StubURLProtocol.register(.response(status: 200, body: Data(#"{"status":"ok"}"#.utf8)))
        let client = URLSessionHTTPClient(baseURL: stubBaseURL.appending(path: "api"), session: session)

        _ = try await HealthService(client: client).fetchHealth()

        #expect(StubURLProtocol.requests(for: stubBaseURL).first?.url?.path() == "/api/healthz")
    }

    @Test func serviceCanBeTestedWithMockClient() async throws {
        let client = MockHTTPClient(responseJSON: #"{"status":"ok"}"#)
        let service = HealthService(client: client)

        #expect(try await service.fetchHealth() == .available)
        #expect(client.sentEndpointNames == ["health.status"])
    }
}

/// Мок транспорта: проверяет сервис без `URLSession`.
final class MockHTTPClient: HTTPClient {
    private let responseJSON: String
    private let names = Mutex<[String]>([])

    init(responseJSON: String) {
        self.responseJSON = responseJSON
    }

    var sentEndpointNames: [String] { names.withLock { $0 } }

    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        names.withLock { $0.append(endpoint.name) }
        return try JSONDecoder().decode(Response.self, from: Data(responseJSON.utf8))
    }
}
