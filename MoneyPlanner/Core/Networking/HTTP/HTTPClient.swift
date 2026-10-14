// HTTPClient.swift
// Общий HTTP-клиент: единственное место работы с URLSession.
// Строит запросы из Endpoint, проверяет ответы и разделяет ошибки транспорта, HTTP и декодирования.

// Foundation нужен для URLSession, URLRequest и JSON-кодеров.
import Foundation
// os нужен для системного логгера Logger.
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
    /// Origin бэкенда, к которому добавляется путь endpoint.
    private let baseURL: URL
    /// Сессия для запросов; в тестах — сессия с `StubURLProtocol`.
    private let session: URLSession
    /// Логгер сетевого слоя (без URL, тел и токенов).
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MoneyPlanner", category: "network")

    /// Создаёт клиент для заданного сервера.
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL // Сохраняем адрес сервера.
        self.session = session // Сохраняем сессию (внедряется в тестах).
    }

    /// Выполняет запрос вне главного актора и возвращает декодированный ответ.
    @concurrent
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try makeRequest(for: endpoint) // Строим URLRequest из описания endpoint.
        let started = ContinuousClock.now // Время начала для измерения длительности.

        let data: Data // Тело ответа.
        let response: URLResponse // Метаданные ответа.
        do {
            (data, response) = try await session.data(for: request) // Выполняем запрос.
        } catch let error as URLError where error.code == .cancelled { // URLSession сообщает об отмене задачи кодом .cancelled.
            throw CancellationError() // Отмену пробрасываем как отмену, а не как сетевую ошибку.
        } catch let error as URLError { // Прочие ошибки транспорта.
            try Task.checkCancellation() // Если задачу отменили одновременно с ошибкой — это отмена.
            logger.notice("\(endpoint.name, privacy: .public) transport error \(error.code.rawValue)") // Логируем только имя операции и код.
            throw NetworkError.transport(error.code) // Ошибка транспорта с кодом URLError.
        } catch is CancellationError { // Отмена, пришедшая из async-кода.
            throw CancellationError() // Сохраняем отмену как есть.
        } catch { // Неизвестная ошибка транспорта.
            try Task.checkCancellation() // Сначала проверяем, не отменена ли задача.
            throw NetworkError.transport(.unknown) // Иначе — ошибка транспорта неизвестного вида.
        }
        try Task.checkCancellation() // Задачу могли отменить после получения ответа.

        guard let httpResponse = response as? HTTPURLResponse else { // Ожидаем именно HTTP-ответ.
            throw NetworkError.invalidResponse // Иной тип ответа не поддерживается.
        }
        let requestID = httpResponse.value(forHTTPHeaderField: "X-Request-Id") // Идентификатор запроса для диагностики.
        // В лог попадают только имя операции, статус, длительность и requestId:
        // без URL, query, заголовков и тел (там могут быть токены и персональные данные).
        logger.debug("""
            \(endpoint.name, privacy: .public) \(httpResponse.statusCode) \
            \(started.duration(to: .now).formatted(.units(allowed: [.milliseconds])), privacy: .public) \
            \(requestID ?? "-", privacy: .public)
            """) // Строка лога: операция, статус, длительность, requestId.

        guard (200..<300).contains(httpResponse.statusCode) else { // Успешны только статусы 2xx.
            throw NetworkError.http(Self.makeHTTPError(response: httpResponse, data: data)) // Ошибка HTTP с разобранным телом.
        }
        return try Self.decode(Response.self, from: data) // Декодируем тело успешного ответа.
    }

    // MARK: - Request

    /// Строит `URLRequest`: URL с query, метод, заголовки и JSON-тело.
    func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        let url = baseURL.appending(path: endpoint.path) // Добавляем путь endpoint к base URL.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { // Разбираем URL для добавления query.
            throw NetworkError.invalidURL // URL не разбирается.
        }
        if !endpoint.query.isEmpty { // Query добавляем только если параметры есть.
            components.queryItems = endpoint.query // URLComponents кодирует параметры.
            // URLComponents не кодирует «+», а сервер читает его как пробел.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B") // Явно кодируем «+».
        }
        guard let finalURL = components.url else { throw NetworkError.invalidURL } // Итоговый URL запроса.

        var request = URLRequest(url: finalURL, timeoutInterval: endpoint.timeout) // Запрос с таймаутом endpoint.
        request.httpMethod = endpoint.method.rawValue // HTTP-метод.
        request.setValue("application/json", forHTTPHeaderField: "Accept") // Ожидаем JSON в ответе.
        if let body = endpoint.body { // Тело есть только у части запросов.
            do {
                request.httpBody = try JSONEncoder().encode(body) // Кодируем тело в JSON.
            } catch {
                throw NetworkError.encoding // Тело не кодируется.
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type") // Сообщаем серверу тип тела.
        }
        for (field, value) in endpoint.headers { // Дополнительные заголовки endpoint.
            request.setValue(value, forHTTPHeaderField: field) // Устанавливаем заголовок.
        }
        return request // Готовый запрос.
    }

    // MARK: - Response

    /// Декодирует тело успешного ответа; для `EmptyResponse` тело не читается.
    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        if let empty = EmptyResponse() as? Response { // Endpoint без тела ответа.
            return empty // Тело игнорируем, даже если оно пришло.
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data) // Декодируем JSON по контракту.
        } catch let error as DecodingError { // Тело не соответствует контракту.
            throw NetworkError.decoding(path: error.codingPathDescription) // Сохраняем только путь до поля, без значений.
        } catch { // Прочие ошибки декодера.
            throw NetworkError.decoding(path: "") // Путь неизвестен.
        }
    }

    /// Собирает `HTTPError` из ответа: статус, тело бэкенда, `Retry-After`, `X-Request-Id`.
    static func makeHTTPError(response: HTTPURLResponse, data: Data) -> HTTPError {
        let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error // Тело ошибки бэкенда, если оно есть.
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After") // Заголовок задержки повтора.
            .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) } // Значение в секундах.
        return HTTPError(
            status: response.statusCode, // HTTP-статус.
            payload: payload, // Разобранное тело или nil.
            retryAfter: retryAfter, // Задержка повтора или nil.
            requestID: response.value(forHTTPHeaderField: "X-Request-Id") ?? payload?.requestId // requestId из заголовка, иначе из тела.
        )
    }
}

/// Описание ошибки декодирования без данных ответа.
private extension DecodingError {
    /// Путь до поля без значений из ответа.
    nonisolated var codingPathDescription: String {
        let path: [any CodingKey] // Путь до поля, где декодирование не удалось.
        switch self { // Контекст есть у всех известных видов ошибки.
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
             .keyNotFound(_, let context), .dataCorrupted(let context): // Берём путь из контекста.
            path = context.codingPath // Ключи до проблемного поля.
        @unknown default: // Новые виды ошибок в будущих SDK.
            path = [] // Путь неизвестен.
        }
        return path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") // Индексы массивов и ключи через точку.
    }
}
