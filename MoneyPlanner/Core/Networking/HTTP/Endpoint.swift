// Endpoint.swift
// Описание HTTP-запроса к API: метод, путь, параметры, заголовки, тело и тип ответа.

// Foundation нужен для URLQueryItem и TimeInterval.
import Foundation

/// HTTP-метод запроса.
nonisolated enum HTTPMethod: String, Sendable {
    /// Чтение данных.
    case get = "GET"
    /// Создание или выполнение действия.
    case post = "POST"
    /// Полная замена ресурса.
    case put = "PUT"
    /// Частичное изменение ресурса.
    case patch = "PATCH"
    /// Удаление ресурса.
    case delete = "DELETE"
}

/// Ответ без тела (например, `204 No Content`). Тело, если оно пришло, игнорируется.
nonisolated struct EmptyResponse: Decodable, Sendable, Equatable {}

/// Описание запроса к API: путь, метод, параметры и ожидаемый тип ответа.
///
/// Endpoint создаются только внутри `Core/Networking/API`. Вызывающий код получает
/// готовый метод сервиса и не видит путей, заголовков и JSON.
nonisolated struct Endpoint<Response: Decodable & Sendable>: Sendable {
    /// Короткое имя операции для логов. Не содержит идентификаторов и пользовательских данных.
    let name: String
    /// HTTP-метод.
    let method: HTTPMethod
    /// Путь относительно base URL, включая версию API, например `/v1/me`.
    let path: String
    /// Query-параметры; пустой массив — без query.
    let query: [URLQueryItem]
    /// Дополнительные заголовки (например, `Idempotency-Key`).
    let headers: [String: String]
    /// Тело запроса; кодируется в JSON HTTP-клиентом.
    let body: (any Encodable & Sendable)?
    /// Таймаут запроса в секундах.
    let timeout: TimeInterval

    /// Создаёт описание запроса.
    /// - Parameter responseType: тип ответа; нужен, чтобы указать `Response` без явного generic-параметра.
    init(
        name: String, // Имя операции для логов.
        method: HTTPMethod, // HTTP-метод.
        path: String, // Путь относительно base URL.
        query: [URLQueryItem] = [], // По умолчанию без query.
        headers: [String: String] = [:], // По умолчанию без дополнительных заголовков.
        body: (any Encodable & Sendable)? = nil, // По умолчанию без тела.
        timeout: TimeInterval = 30, // Таймаут по умолчанию — 30 секунд.
        responseType: Response.Type = Response.self // Подсказка компилятору для вывода Response.
    ) {
        self.name = name // Сохраняем имя операции.
        self.method = method // Сохраняем метод.
        self.path = path // Сохраняем путь.
        self.query = query // Сохраняем query-параметры.
        self.headers = headers // Сохраняем заголовки.
        self.body = body // Сохраняем тело.
        self.timeout = timeout // Сохраняем таймаут.
    }
}
