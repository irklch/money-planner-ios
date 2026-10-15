// NetworkError.swift
// Ошибки сетевого слоя и формат ошибки бэкенда.

// Foundation нужен для URLError и TimeInterval.
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
        switch self { // Решение зависит от вида ошибки.
        case .transport(let code): // Ошибка транспорта.
            Self.retryableTransportCodes.contains(code) // Повторяем только временные сетевые сбои.
        case .http(let error): // Ответ сервера с ошибкой.
            error.status == 429 || (500...599).contains(error.status) || error.payload?.retryable == true // Лимит частоты, 5xx или явный флаг сервера.
        case .invalidURL, .encoding, .invalidResponse, .decoding: // Ошибки клиента и контракта.
            false // Повтор не поможет.
        }
    }

    /// Коды URLError, означающие временную проблему сети.
    private static let retryableTransportCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost, // Нет сети, таймаут, обрыв, хост недоступен.
        .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, // Ошибки DNS и ограничения мобильных данных.
    ]
}

/// HTTP-ответ с ошибкой.
nonisolated struct HTTPError: Sendable, Equatable {
    /// HTTP-статус ответа.
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
    /// Подробность ошибки валидации.
    nonisolated struct Detail: Decodable, Sendable, Equatable {
        /// Машиночитаемый код подробности, например `amount_invalid`.
        let code: String
        /// Имя поля запроса, к которому относится ошибка.
        let field: String?
        /// Индекс элемента в массиве запроса.
        let index: Int?
    }

    /// Машиночитаемый код, например `rate_limited`. Список кодов меняется вместе с контрактом,
    /// поэтому хранится строкой.
    let code: String
    /// Техническое сообщение для логов; пользователю не показывается.
    let message: String
    /// HTTP-статус, продублированный в теле.
    let status: Int
    /// Сервер считает запрос безопасным для повтора.
    let retryable: Bool
    /// Идентификатор запроса для диагностики.
    let requestId: String?
    /// Подробности ошибки (для `validation_failed`).
    let details: [Detail]
}

/// Обёртка `{ "error": … }`.
nonisolated struct APIErrorEnvelope: Decodable, Sendable {
    /// Ошибка внутри обёртки.
    let error: APIErrorPayload
}
