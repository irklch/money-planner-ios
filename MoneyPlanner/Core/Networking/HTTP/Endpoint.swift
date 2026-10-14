import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
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
    let method: HTTPMethod
    /// Путь относительно base URL, включая версию API, например `/v1/me`.
    let path: String
    let query: [URLQueryItem]
    let headers: [String: String]
    let body: (any Encodable & Sendable)?
    let timeout: TimeInterval

    init(
        name: String,
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        timeout: TimeInterval = 30,
        responseType: Response.Type = Response.self
    ) {
        self.name = name
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}
