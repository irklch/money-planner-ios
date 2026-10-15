// AppDependencies.swift
// Корень композиции: сборка всех зависимостей приложения в одном месте.

// Foundation нужен для базовых типов.
import Foundation
// SwiftData нужен для ModelContainer.
import SwiftData

/// Корень композиции: все зависимости собираются здесь и передаются дальше через инициализаторы.
final class AppDependencies {
    /// Конфигурация окружения (base URL, версия).
    let configuration: AppConfiguration
    /// Контейнер локальной БД.
    let modelContainer: ModelContainer
    /// Хранилище настроек приложения.
    let settingsStore: any AppSettingsStoring
    /// Хранилище расходов, категорий и отметок дня (один актор на контейнер).
    let ledger: LedgerStore
    /// `nil`, если адрес API не настроен или сеть запрещена режимом запуска.
    let healthService: (any HealthServicing)?

    /// Создаёт набор зависимостей из готовых компонентов (previews и тесты).
    init(
        configuration: AppConfiguration, // Конфигурация окружения.
        modelContainer: ModelContainer, // Контейнер БД.
        settingsStore: any AppSettingsStoring, // Хранилище настроек.
        ledger: LedgerStore, // Хранилище расходов и категорий.
        healthService: (any HealthServicing)? // Сервис health-check или nil.
    ) {
        self.configuration = configuration // Сохраняем конфигурацию.
        self.modelContainer = modelContainer // Сохраняем контейнер БД.
        self.settingsStore = settingsStore // Сохраняем хранилище настроек.
        self.ledger = ledger // Сохраняем хранилище расходов и категорий.
        self.healthService = healthService // Сохраняем сервис health-check.
    }

    /// Сборка для запуска приложения и тестов.
    /// - Throws: ошибку открытия БД. Ошибка показывается пользователю с повторной попыткой.
    static func make(mode: LaunchMode, configuration: AppConfiguration) throws -> AppDependencies {
        let container = mode.usesPersistentStore // Выбор хранилища зависит от режима запуска.
            ? try ModelContainerFactory.makePersistent() // Приложение — пользовательская БД на диске.
            : try ModelContainerFactory.makeInMemory() // Тесты и previews — временная БД в памяти.

        var healthService: (any HealthServicing)? // Сервис создаётся только при разрешённой сети.
        if mode.allowsNetwork, let baseURL = configuration.apiBaseURL { // Нужны и режим с сетью, и настроенный адрес.
            healthService = HealthService(client: URLSessionHTTPClient(baseURL: baseURL)) // Сервис поверх общего HTTP-клиента.
        }

        return AppDependencies( // Готовый набор зависимостей.
            configuration: configuration, // Конфигурация окружения.
            modelContainer: container, // Выбранный контейнер БД.
            settingsStore: AppSettingsRepository(container: container), // Репозиторий настроек поверх контейнера.
            ledger: LedgerStore(container: container), // Единственный актор данных поверх того же контейнера.
            healthService: healthService // Сервис или nil.
        )
    }

    /// Категории для ViewModel.
    var categoryRepository: any CategoryRepository { ledger } // Тот же актор, узкий протокол.
    /// Расходы для ViewModel.
    var expenseRepository: any ExpenseRepository { ledger } // Тот же актор, узкий протокол.
    /// Отметки дня для ViewModel.
    var dayMarkRepository: any DayMarkRepository { ledger } // Тот же актор, узкий протокол.
}
