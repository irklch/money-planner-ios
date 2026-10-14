// RootView.swift
// Корневой экран с нативной навигацией и вспомогательные зависимости для previews.

// SwiftUI нужен для View и NavigationStack.
import SwiftUI

/// Маршруты нативной навигации. Экраны добавляются сюда по мере появления фич.
enum AppRoute: Hashable {}

/// Корневой экран: `NavigationStack` с путём навигации и временным экраном проверки запуска.
struct RootView: View {
    /// Зависимости приложения из корня композиции.
    let dependencies: AppDependencies

    /// Путь навигации; сюда будут добавляться маршруты экранов.
    @State private var path: [AppRoute] = []
    /// ViewModel временного экрана проверки запуска; живёт вместе с RootView.
    @State private var launchCheckModel: LaunchCheckViewModel

    /// Создаёт корневой экран и ViewModel первого экрана из зависимостей.
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies // Сохраняем зависимости.
        _launchCheckModel = State(initialValue: LaunchCheckViewModel( // ViewModel создаётся один раз.
            configuration: dependencies.configuration, // Версия приложения для подписи.
            settingsStore: dependencies.settingsStore, // Хранилище настроек.
            healthService: dependencies.healthService // Сервис health-check или nil.
        ))
    }

    /// Содержимое корневого экрана.
    var body: some View {
        NavigationStack(path: $path) { // Нативный стек навигации с управляемым путём.
            // С первым маршрутом здесь появится
            // `.navigationDestination(for: AppRoute.self) { route in switch route { … } }`.
            LaunchCheckView(model: launchCheckModel) // Временный экран проверки запуска.
        }
        .accessibilityIdentifier("root") // Идентификатор для UI-тестов.
    }
}

/// Preview корневого экрана при обычном размере текста.
#Preview("RootView") {
    RootView(dependencies: .preview()) // Зависимости без сети и с временной БД.
}

/// Preview корневого экрана при крупном размере текста.
#Preview("RootView, AX3") {
    RootView(dependencies: .preview()) // Зависимости без сети и с временной БД.
        .environment(\.dynamicTypeSize, .accessibility3) // Крупный Dynamic Type.
}

/// Зависимости для previews.
extension AppDependencies {
    /// Зависимости для previews: временная БД и сервис без сети.
    static func preview(health: Result<ServerHealth, NetworkError> = .success(.available)) -> AppDependencies {
        let container = try! ModelContainerFactory.makeInMemory() // В previews ошибка БД в памяти невозможна на практике.
        return AppDependencies( // Набор зависимостей для preview.
            configuration: AppConfiguration(apiBaseURL: nil, appVersion: "1.0", buildNumber: "1"), // Без адреса API.
            modelContainer: container, // Временная БД.
            settingsStore: AppSettingsRepository(container: container), // Репозиторий поверх временной БД.
            healthService: PreviewHealthService(result: health) // Сервис с заранее заданным ответом.
        )
    }
}

/// Сервис health-check для previews: отвечает заданным результатом без сети.
nonisolated struct PreviewHealthService: HealthServicing {
    /// Результат, который вернёт сервис.
    let result: Result<ServerHealth, NetworkError>

    /// Возвращает заданный результат или ошибку.
    func fetchHealth() async throws -> ServerHealth {
        try result.get() // Значение или ошибка из result.
    }
}
