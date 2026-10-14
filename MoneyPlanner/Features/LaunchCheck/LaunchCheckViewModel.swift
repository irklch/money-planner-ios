// LaunchCheckViewModel.swift
// Состояние временного экрана проверки запуска: локальные настройки и ручная проверка сервера.

// Foundation нужен для базовых типов.
import Foundation
// Observation нужен для макроса @Observable.
import Observation

/// Временный экран проверки запуска: состояние локальной БД и ручная проверка сервера.
@Observable
final class LaunchCheckViewModel {
    /// Состояние чтения локальных настроек.
    enum StorageState: Equatable {
        /// Настройки ещё читаются.
        case loading
        /// Настройки прочитаны.
        case ready(AppSettingsSnapshot)
        /// Настройки прочитать не удалось.
        case failed
    }

    /// Состояние проверки сервера.
    enum ServerState: Equatable {
        /// Адрес API не задан или сеть отключена режимом запуска.
        case notConfigured
        /// Проверка ещё не запускалась.
        case idle
        /// Идёт запрос.
        case checking
        /// Сервер доступен.
        case available
        /// Сервер отвечает, но не в рабочем состоянии.
        case degraded
        /// Проверка завершилась ошибкой.
        case failed(ServerFailure)
    }

    /// Пользовательская категория ошибки. Технические детали сервера не показываются.
    enum ServerFailure: Equatable {
        /// Нет сети или сервер недостижим.
        case noConnection
        /// Сервер временно недоступен (5xx, 429).
        case unavailable
        /// Прочие ошибки.
        case unexpected
    }

    /// Состояние локальных настроек для экрана.
    private(set) var storage: StorageState = .loading
    /// Состояние проверки сервера для экрана.
    private(set) var server: ServerState
    /// Версия приложения для подписи.
    let appVersion: String
    /// Номер сборки для подписи.
    let buildNumber: String

    /// Хранилище настроек.
    private let settingsStore: any AppSettingsStoring
    /// Сервис проверки сервера; `nil`, если сеть недоступна.
    private let healthService: (any HealthServicing)?

    /// Создаёт ViewModel из зависимостей.
    init(
        configuration: AppConfiguration, // Источник версии приложения.
        settingsStore: any AppSettingsStoring, // Хранилище настроек.
        healthService: (any HealthServicing)? // Сервис health-check или nil.
    ) {
        self.appVersion = configuration.appVersion // Версия для подписи.
        self.buildNumber = configuration.buildNumber // Номер сборки для подписи.
        self.settingsStore = settingsStore // Сохраняем хранилище.
        self.healthService = healthService // Сохраняем сервис.
        self.server = healthService == nil ? .notConfigured : .idle // Без сервиса проверка недоступна.
    }

    /// Читает настройки из локальной БД.
    func loadSettings() {
        do {
            storage = .ready(try settingsStore.load()) // Показываем прочитанные настройки.
        } catch {
            storage = .failed // Показываем ошибку чтения.
        }
    }

    /// Один запрос health-check. Отмена (уход с экрана) возвращает исходное состояние.
    func checkServer() async {
        guard let healthService else { return } // Без сервиса проверять нечего.
        server = .checking // Показываем индикатор проверки.
        do {
            server = switch try await healthService.fetchHealth() { // Запрос к серверу.
            case .available: .available // Сервер работает.
            case .degraded: .degraded // Сервер отвечает с проблемой.
            }
        } catch is CancellationError { // Пользователь ушёл с экрана.
            server = .idle // Возвращаем исходное состояние без ошибки.
        } catch let error as NetworkError { // Ошибка сетевого слоя.
            server = .failed(Self.failure(for: error)) // Переводим в пользовательскую категорию.
        } catch { // Неизвестная ошибка.
            server = .failed(.unexpected) // Общая ошибка.
        }
    }

    /// Переводит сетевую ошибку в пользовательскую категорию.
    static func failure(for error: NetworkError) -> ServerFailure {
        switch error { // Категория зависит от вида ошибки.
        case .transport: // Нет сети, таймаут и т. п.
            .noConnection // «Нет соединения».
        case .http(let httpError) where httpError.status == 429 || httpError.status >= 500: // Перегрузка или сбой сервера.
            .unavailable // «Сервис временно недоступен».
        case .http, .invalidURL, .encoding, .invalidResponse, .decoding: // Ошибки клиента и контракта.
            .unexpected // «Что-то пошло не так».
        }
    }
}
