import Foundation
import Testing
@testable import MoneyPlanner

@MainActor
@Suite("LaunchCheckViewModel")
struct LaunchCheckViewModelTests {
    private struct StubHealthService: HealthServicing {
        let result: Result<ServerHealth, any Error>
        func fetchHealth() async throws -> ServerHealth { try result.get() }
    }

    private func makeModel(health: (any HealthServicing)?) throws -> LaunchCheckViewModel {
        let container = try ModelContainerFactory.makeInMemory()
        return LaunchCheckViewModel(
            configuration: AppConfiguration(apiBaseURL: nil, appVersion: "1.0", buildNumber: "1"),
            settingsStore: AppSettingsRepository(container: container),
            ledgerSummary: LedgerStore(container: container), // Хранилище данных поверх той же временной БД.
            healthService: health
        )
    }

    @Test func withoutServiceServerIsNotConfigured() async throws {
        let model = try makeModel(health: nil)
        await model.checkServer()
        #expect(model.server == .notConfigured)
    }

    @Test func loadsSettings() throws {
        let model = try makeModel(health: nil)
        model.loadSettings()
        guard case .ready(let settings) = model.storage else {
            Issue.record("Settings were not loaded")
            return
        }
        #expect(settings.hasCompletedOnboarding == false)
    }

    /// Подготовка хранилища создаёт 12 системных категорий и показывает сводку.
    @Test func preparesLedgerWithSystemCategories() async throws {
        // ViewModel без сети.
        let model = try makeModel(health: nil)
        await model.loadLedger() // Подготовка хранилища.
        #expect(model.ledger == .ready(LedgerSummary(activeCategoryCount: SystemCategory.allCases.count, expenseCount: 0))) // 12 категорий, расходов нет.
    }

    @Test(arguments: [
        (Result<ServerHealth, any Error>.success(.available), LaunchCheckViewModel.ServerState.available),
        (.success(.degraded), .degraded),
        (.failure(NetworkError.transport(.timedOut)), .failed(.noConnection)),
        (.failure(NetworkError.http(HTTPError(status: 503, payload: nil, retryAfter: nil, requestID: nil))), .failed(.unavailable)),
        (.failure(NetworkError.http(HTTPError(status: 404, payload: nil, retryAfter: nil, requestID: nil))), .failed(.unexpected)),
        (.failure(NetworkError.decoding(path: "status")), .failed(.unexpected)),
        (.failure(CancellationError()), .idle),
    ])
    func mapsHealthResult(result: Result<ServerHealth, any Error>, expected: LaunchCheckViewModel.ServerState) async throws {
        let model = try makeModel(health: StubHealthService(result: result))
        await model.checkServer()
        #expect(model.server == expected)
    }
}
