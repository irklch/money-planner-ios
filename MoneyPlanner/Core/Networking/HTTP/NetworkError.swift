import Foundation

/// Ошибка сетевого слоя. Отмена задачи сюда не попадает: она пробрасывается как `CancellationError`.
nonisolated enum NetworkError: Error, Sendable, Equatable {
    /// Не удалось построить URL запроса.
    case invalidURL
    /// Не удалось закодировать тело запроса.
    case encoding
    /// Ошибка транспорта: нет сети, таймаут, TLS и т. п.
    case transport(URLError.Code)
    /// Ответ не является HTTP-ответом.
    case invalidResponse
    /// Сервер ответил статусом вне 2xx.
    case http(HTTPError)
    /// Тело успешного ответа не соответствует контракту.
    case decoding(path: String)

    /// Ошибку имеет смысл повторить автоматически (план миграции backend, §8.1):
    /// нет сети, таймаут, `5xx`, `429` или `retryable` из тела ошибки.
    var isRetryable: Bool {
        switch self {
        case .transport(let code):
            Self.retryableTransportCodes.contains(code)
        case .http(let error):
            error.status == 429 || (500...599).contains(error.status) || error.payload?.retryable == true
        case .invalidURL, .encoding, .invalidResponse, .decoding:
            false
        }
    }

    private static let retryableTransportCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]
}

/// HTTP-ответ с ошибкой.
nonisolated struct HTTPError: Sendable, Equatable {
    let status: Int
    /// Тело ошибки в формате бэкенда, если его удалось разобрать.
    let payload: APIErrorPayload?
    /// `Retry-After` в секундах.
    let retryAfter: TimeInterval?
    /// `X-Request-Id` для диагностики.
    let requestID: String?
}

/// Единый формат ошибки бэкенда (`app/core/errors.py`, «09 — Error Model»):
/// `{ "error": { code, message, status, retryable, requestId, details: [{ code, field?, index? }] } }`.
///
/// `message` предназначено только для логов и никогда не показывается пользователю.
nonisolated struct APIErrorPayload: Decodable, Sendable, Equatable {
    nonisolated struct Detail: Decodable, Sendable, Equatable {
        let code: String
        let field: String?
        let index: Int?
    }

    /// Машиночитаемый код, например `rate_limited`. Список кодов меняется вместе с контрактом,
    /// поэтому хранится строкой.
    let code: String
    let message: String
    let status: Int
    let retryable: Bool
    let requestId: String?
    let details: [Detail]
}

/// Обёртка `{ "error": … }`.
nonisolated struct APIErrorEnvelope: Decodable, Sendable {
    let error: APIErrorPayload
}
