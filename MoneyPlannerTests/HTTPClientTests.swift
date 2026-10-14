import Foundation
import Testing
@testable import MoneyPlanner

@Suite("URLSessionHTTPClient")
struct HTTPClientTests {
    private struct Payload: Codable, Sendable, Equatable {
        let name: String
        let amount: String
    }

    private static let sampleEndpoint = Endpoint<Payload>(
        name: "test.create",
        method: .post,
        path: "/v1/items",
        query: [URLQueryItem(name: "q", value: "a+b c"), URLQueryItem(name: "limit", value: "10")],
        headers: ["Idempotency-Key": "00000000-0000-0000-0000-000000000001"],
        body: Payload(name: "Кофе", amount: "250.50")
    )

    private func makeClient(_ stub: StubURLProtocol.Stub) -> (URLSessionHTTPClient, URL) {
        let (baseURL, session) = StubURLProtocol.register(stub)
        return (URLSessionHTTPClient(baseURL: baseURL, session: session), baseURL)
    }

    @Test func successfulResponseIsDecodedAndRequestIsBuilt() async throws {
        let body = Data(#"{"name":"Кофе","amount":"250.50","extra":true}"#.utf8)
        let (client, baseURL) = makeClient(.response(status: 201, body: body))

        let result = try await client.send(Self.sampleEndpoint)

        #expect(result == Payload(name: "Кофе", amount: "250.50"))
        let request = try #require(StubURLProtocol.requests(for: baseURL).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/items")
        #expect(request.url?.query(percentEncoded: true) == "q=a%2Bb%20c&limit=10")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "00000000-0000-0000-0000-000000000001")
        let sentBody = try JSONDecoder().decode(Payload.self, from: try #require(request.httpBody))
        #expect(sentBody == Payload(name: "Кофе", amount: "250.50"))
    }

    @Test(arguments: [200, 204])
    func responseWithoutBody(status: Int) async throws {
        let (client, baseURL) = makeClient(.response(status: status))
        let endpoint = Endpoint<EmptyResponse>(name: "test.delete", method: .delete, path: "/v1/items/1")

        let result = try await client.send(endpoint)

        #expect(result == EmptyResponse())
        let request = try #require(StubURLProtocol.requests(for: baseURL).first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test func serverErrorIsParsedFromBackendFormat() async throws {
        let body = Data("""
            {"error":{"code":"idempotency_in_progress","message":"Request with this idempotency key is in progress",
            "status":409,"retryable":true,"requestId":"req_body","details":[{"code":"amount_invalid","field":"amount","index":2}]}}
            """.utf8)
        let (client, _) = makeClient(.response(
            status: 409,
            headers: ["Retry-After": "3", "X-Request-Id": "req_header", "Content-Type": "application/json"],
            body: body
        ))

        let error = await #expect(throws: NetworkError.self) {
            try await client.send(HealthAPI.status)
        }

        let expected = HTTPError(
            status: 409,
            payload: APIErrorPayload(
                code: "idempotency_in_progress",
                message: "Request with this idempotency key is in progress",
                status: 409,
                retryable: true,
                requestId: "req_body",
                details: [.init(code: "amount_invalid", field: "amount", index: 2)]
            ),
            retryAfter: 3,
            requestID: "req_header"
        )
        #expect(error == .http(expected))
        #expect(error?.isRetryable == true)
    }

    @Test func serverErrorWithoutBackendBodyKeepsStatus() async throws {
        let (client, _) = makeClient(.response(status: 502, body: Data("<html>Bad gateway</html>".utf8)))

        let error = await #expect(throws: NetworkError.self) {
            try await client.send(HealthAPI.status)
        }

        #expect(error == .http(HTTPError(status: 502, payload: nil, retryAfter: nil, requestID: nil)))
        #expect(error?.isRetryable == true)
    }

    @Test func notFoundIsNotRetryable() async throws {
        let body = Data(#"{"error":{"code":"not_found","message":"Not found","status":404,"retryable":false,"requestId":"r","details":[]}}"#.utf8)
        let (client, _) = makeClient(.response(status: 404, body: body))

        let error = await #expect(throws: NetworkError.self) {
            try await client.send(HealthAPI.status)
        }

        #expect(error?.isRetryable == false)
    }

    @Test func invalidJSONIsDecodingError() async throws {
        let (client, _) = makeClient(.response(status: 200, body: Data("{".utf8)))

        await #expect(throws: NetworkError.decoding(path: "")) {
            try await client.send(HealthAPI.status)
        }
    }

    @Test func unexpectedTypeIsDecodingErrorWithPath() async throws {
        let (client, _) = makeClient(.response(status: 200, body: Data(#"{"status":1}"#.utf8)))

        await #expect(throws: NetworkError.decoding(path: "status")) {
            try await client.send(HealthAPI.status)
        }
    }

    @Test func transportErrorIsPreserved() async throws {
        let (client, _) = makeClient(.failure(.notConnectedToInternet))

        let error = await #expect(throws: NetworkError.self) {
            try await client.send(HealthAPI.status)
        }

        #expect(error == .transport(.notConnectedToInternet))
        #expect(error?.isRetryable == true)
    }

    @Test func cancellationIsReportedAsCancellation() async throws {
        let (client, baseURL) = makeClient(.hang)
        let task = Task { try await client.send(HealthAPI.status) }

        try await StubURLProtocol.waitForRequest(to: baseURL)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
