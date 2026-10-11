import Foundation
import Synchronization

/// Подменяет сеть в тестах через `URLProtocol`, без реального сервера.
///
/// Каждый тест получает уникальный хост, поэтому параллельные тесты не мешают друг другу.
final class StubURLProtocol: URLProtocol {
    enum Stub: Sendable {
        case response(status: Int, headers: [String: String] = [:], body: Data = Data())
        case failure(URLError.Code)
        /// Не отвечает, пока запрос не отменят.
        case hang
    }

    private struct Entry {
        let stub: Stub
        var requests: [URLRequest] = []
    }

    private static let entries = Mutex<[String: Entry]>([:])

    /// Регистрирует ответ для уникального хоста и возвращает base URL и сессию.
    static func register(_ stub: Stub) -> (baseURL: URL, session: URLSession) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        entries.withLock { $0[host] = Entry(stub: stub) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return (URL(string: "https://\(host)")!, URLSession(configuration: configuration))
    }

    /// Запросы, полученные для хоста base URL, с прочитанным телом.
    static func requests(for baseURL: URL) -> [URLRequest] {
        entries.withLock { $0[baseURL.host() ?? ""]?.requests ?? [] }
    }

    /// Ждёт первый запрос к хосту (для тестов отмены).
    static func waitForRequest(to baseURL: URL, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while requests(for: baseURL).isEmpty {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        var recorded = request
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        let stub = Self.entries.withLock { entries -> Stub? in
            entries[host]?.requests.append(recorded)
            return entries[host]?.stub
        }

        switch stub {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang:
            break
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
