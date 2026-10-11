import SwiftUI

/// Маршруты нативной навигации. Экраны добавляются сюда по мере появления фич.
enum AppRoute: Hashable {}

/// Корневой экран: `NavigationStack` с путём навигации и временным экраном проверки запуска.
struct RootView: View {
    let dependencies: AppDependencies

    @State private var path: [AppRoute] = []
    @State private var launchCheckModel: LaunchCheckViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _launchCheckModel = State(initialValue: LaunchCheckViewModel(
            configuration: dependencies.configuration,
            settingsStore: dependencies.settingsStore,
            healthService: dependencies.healthService
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            // С первым маршрутом здесь появится
            // `.navigationDestination(for: AppRoute.self) { route in switch route { … } }`.
            LaunchCheckView(model: launchCheckModel)
        }
        .accessibilityIdentifier("root")
    }
}

#Preview("RootView") {
    RootView(dependencies: .preview())
}

#Preview("RootView, AX3") {
    RootView(dependencies: .preview())
        .environment(\.dynamicTypeSize, .accessibility3)
}

extension AppDependencies {
    /// Зависимости для previews: временная БД и сервис без сети.
    static func preview(health: Result<ServerHealth, NetworkError> = .success(.available)) -> AppDependencies {
        let container = try! ModelContainerFactory.makeInMemory()
        return AppDependencies(
            configuration: AppConfiguration(apiBaseURL: nil, appVersion: "1.0", buildNumber: "1"),
            modelContainer: container,
            settingsStore: AppSettingsRepository(container: container),
            healthService: PreviewHealthService(result: health)
        )
    }
}

/// Сервис health-check для previews: отвечает заданным результатом без сети.
nonisolated struct PreviewHealthService: HealthServicing {
    let result: Result<ServerHealth, NetworkError>

    func fetchHealth() async throws -> ServerHealth {
        try result.get()
    }
}
