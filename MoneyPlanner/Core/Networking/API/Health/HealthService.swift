import Foundation

/// Состояние сервера по ответу health-check.
nonisolated enum ServerHealth: Sendable, Equatable {
    /// Сервер ответил `status: "ok"`.
    case available
    /// Сервер ответил, но с другим статусом.
    case degraded
}

/// Проверка доступности бэкенда.
nonisolated protocol HealthServicing: Sendable {
    func fetchHealth() async throws -> ServerHealth
}

/// Сервис на основе `GET /healthz` бэкенда.
///
/// Endpoint реализован в `app/main.py` (main `1943bcd`): без авторизации, только чтение,
/// ответ `{"status": "ok"}`. В `openapi.json` он не входит (`include_in_schema=False`),
/// но заявлен в публичном контракте этапов E0/E1 плана миграции.
nonisolated struct HealthService: HealthServicing {
    private let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    func fetchHealth() async throws -> ServerHealth {
        let response = try await client.send(HealthAPI.status)
        return response.status == HealthStatusDTO.okStatus ? .available : .degraded
    }
}

/// Endpoint health-check. Путь не входит в `/v1`.
nonisolated enum HealthAPI {
    static let status = Endpoint<HealthStatusDTO>(name: "health.status", method: .get, path: "/healthz", timeout: 15)
}

/// Тело ответа `GET /healthz`.
nonisolated struct HealthStatusDTO: Decodable, Sendable, Equatable {
    static let okStatus = "ok"
    let status: String
}
