import Foundation
import Observation

/// Временный экран проверки запуска: состояние локальной БД и ручная проверка сервера.
@Observable
final class LaunchCheckViewModel {
    enum StorageState: Equatable {
        case loading
        case ready(AppSettingsSnapshot)
        case failed
    }

    enum ServerState: Equatable {
        /// Адрес API не задан или сеть отключена режимом запуска.
        case notConfigured
        case idle
        case checking
        case available
        case degraded
        case failed(ServerFailure)
    }

    /// Пользовательская категория ошибки. Технические детали сервера не показываются.
    enum ServerFailure: Equatable {
        case noConnection
        case unavailable
        case unexpected
    }

    private(set) var storage: StorageState = .loading
    private(set) var server: ServerState
    let appVersion: String
    let buildNumber: String

    private let settingsStore: any AppSettingsStoring
    private let healthService: (any HealthServicing)?

    init(
        configuration: AppConfiguration,
        settingsStore: any AppSettingsStoring,
        healthService: (any HealthServicing)?
    ) {
        self.appVersion = configuration.appVersion
        self.buildNumber = configuration.buildNumber
        self.settingsStore = settingsStore
        self.healthService = healthService
        self.server = healthService == nil ? .notConfigured : .idle
    }

    func loadSettings() {
        do {
            storage = .ready(try settingsStore.load())
        } catch {
            storage = .failed
        }
    }

    /// Один запрос health-check. Отмена (уход с экрана) возвращает исходное состояние.
    func checkServer() async {
        guard let healthService else { return }
        server = .checking
        do {
            server = switch try await healthService.fetchHealth() {
            case .available: .available
            case .degraded: .degraded
            }
        } catch is CancellationError {
            server = .idle
        } catch let error as NetworkError {
            server = .failed(Self.failure(for: error))
        } catch {
            server = .failed(.unexpected)
        }
    }

    static func failure(for error: NetworkError) -> ServerFailure {
        switch error {
        case .transport:
            .noConnection
        case .http(let httpError) where httpError.status == 429 || httpError.status >= 500:
            .unavailable
        case .http, .invalidURL, .encoding, .invalidResponse, .decoding:
            .unexpected
        }
    }
}
