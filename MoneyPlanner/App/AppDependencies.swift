import Foundation
import SwiftData

/// Корень композиции: все зависимости собираются здесь и передаются дальше через инициализаторы.
final class AppDependencies {
    let configuration: AppConfiguration
    let modelContainer: ModelContainer
    let settingsStore: any AppSettingsStoring
    /// `nil`, если адрес API не настроен или сеть запрещена режимом запуска.
    let healthService: (any HealthServicing)?

    init(
        configuration: AppConfiguration,
        modelContainer: ModelContainer,
        settingsStore: any AppSettingsStoring,
        healthService: (any HealthServicing)?
    ) {
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.settingsStore = settingsStore
        self.healthService = healthService
    }

    /// Сборка для запуска приложения и тестов.
    /// - Throws: ошибку открытия БД. Ошибка показывается пользователю с повторной попыткой.
    static func make(mode: LaunchMode, configuration: AppConfiguration) throws -> AppDependencies {
        let container = mode.usesPersistentStore
            ? try ModelContainerFactory.makePersistent()
            : try ModelContainerFactory.makeInMemory()

        var healthService: (any HealthServicing)?
        if mode.allowsNetwork, let baseURL = configuration.apiBaseURL {
            healthService = HealthService(client: URLSessionHTTPClient(baseURL: baseURL))
        }

        return AppDependencies(
            configuration: configuration,
            modelContainer: container,
            settingsStore: AppSettingsRepository(container: container),
            healthService: healthService
        )
    }
}
