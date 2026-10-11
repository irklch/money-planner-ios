import Foundation
import os

/// Транспорт для API-сервисов. Подменяется в тестах сервисов.
nonisolated protocol HTTPClient: Sendable {
    /// Выполняет запрос и возвращает декодированный ответ.
    /// - Throws: `NetworkError` или `CancellationError`, если задача отменена.
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response
}

/// Единственное место работы с `URLSession`.
///
/// Строит `URLRequest` из `Endpoint`, кодирует тело, проверяет статус, декодирует ответ
/// и ошибки в формате бэкенда. Работа выполняется вне главного потока.
nonisolated final class URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MoneyPlanner", category: "network")

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    @concurrent
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try makeRequest(for: endpoint)
        let started = ContinuousClock.now

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            try Task.checkCancellation()
            logger.notice("\(endpoint.name, privacy: .public) transport error \(error.code.rawValue)")
            throw NetworkError.transport(error.code)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw NetworkError.transport(.unknown)
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        let requestID = httpResponse.value(forHTTPHeaderField: "X-Request-Id")
        // В лог попадают только имя операции, статус, длительность и requestId:
        // без URL, query, заголовков и тел (там могут быть токены и персональные данные).
        logger.debug("""
            \(endpoint.name, privacy: .public) \(httpResponse.statusCode) \
            \(started.duration(to: .now).formatted(.units(allowed: [.milliseconds])), privacy: .public) \
            \(requestID ?? "-", privacy: .public)
            """)

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.http(Self.makeHTTPError(response: httpResponse, data: data))
        }
        return try Self.decode(Response.self, from: data)
    }

    // MARK: - Request

    func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        let url = baseURL.appending(path: endpoint.path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
            // URLComponents не кодирует «+», а сервер читает его как пробел.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let finalURL = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: finalURL, timeoutInterval: endpoint.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw NetworkError.encoding
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    // MARK: - Response

    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        if let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.decoding(path: error.codingPathDescription)
        } catch {
            throw NetworkError.decoding(path: "")
        }
    }

    static func makeHTTPError(response: HTTPURLResponse, data: Data) -> HTTPError {
        let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
        return HTTPError(
            status: response.statusCode,
            payload: payload,
            retryAfter: retryAfter,
            requestID: response.value(forHTTPHeaderField: "X-Request-Id") ?? payload?.requestId
        )
    }
}

private extension DecodingError {
    /// Путь до поля без значений из ответа.
    nonisolated var codingPathDescription: String {
        let path: [any CodingKey]
        switch self {
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
             .keyNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        @unknown default:
            path = []
        }
        return path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}
