// HealthService.swift
// API-сервис проверки доступности бэкенда на основе GET /healthz: протокол, реализация, endpoint и DTO.

// Foundation нужен для базовых типов.
import Foundation

/// Состояние сервера по ответу health-check.
nonisolated enum ServerHealth: Sendable, Equatable {
    /// Сервер ответил `status: "ok"`.
    case available
    /// Сервер ответил, но с другим статусом.
    case degraded
}

/// Проверка доступности бэкенда. Протокол позволяет подменить сервис моком.
nonisolated protocol HealthServicing: Sendable {
    /// Запрашивает состояние сервера.
    /// - Throws: `NetworkError` или `CancellationError`.
    func fetchHealth() async throws -> ServerHealth
}

/// Сервис на основе `GET /healthz` бэкенда.
///
/// Endpoint реализован в `app/main.py` (main `1943bcd`): без авторизации, только чтение,
/// ответ `{"status": "ok"}`. В `openapi.json` он не входит (`include_in_schema=False`),
/// но заявлен в публичном контракте этапов E0/E1 плана миграции.
nonisolated struct HealthService: HealthServicing {
    /// HTTP-транспорт, через который выполняется запрос.
    private let client: any HTTPClient

    /// Создаёт сервис поверх HTTP-клиента.
    init(client: any HTTPClient) {
        self.client = client // Сохраняем транспорт.
    }

    /// Выполняет health-check и переводит ответ в доменное состояние.
    func fetchHealth() async throws -> ServerHealth {
        let response = try await client.send(HealthAPI.status) // Запрос GET /healthz.
        return response.status == HealthStatusDTO.okStatus ? .available : .degraded // "ok" — доступен, иное — деградация.
    }
}

/// Endpoint health-check. Путь не входит в `/v1`.
nonisolated enum HealthAPI {
    /// `GET /healthz` без авторизации, с коротким таймаутом 15 секунд.
    static let status = Endpoint<HealthStatusDTO>(name: "health.status", method: .get, path: "/healthz", timeout: 15)
}

/// Тело ответа `GET /healthz`.
nonisolated struct HealthStatusDTO: Decodable, Sendable, Equatable {
    /// Значение `status` у работающего сервера.
    static let okStatus = "ok"
    /// Статус сервера из ответа.
    let status: String
}
