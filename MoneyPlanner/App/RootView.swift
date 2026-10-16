// RootView.swift
// Корневой экран с нативной навигацией и вспомогательные зависимости для previews.

// SwiftUI нужен для View и NavigationStack.
import SwiftUI

/// Маршруты нативной навигации.
enum AppRoute: Hashable {
    /// Расходы категории за выбранный период.
    case category(CategoryReference)
}

/// Корневой экран: `NavigationStack` с главным экраном «Обзор» и общим выбранным периодом.
struct RootView: View {
    /// Зависимости приложения из корня композиции.
    let dependencies: AppDependencies

    /// Путь навигации.
    @State private var path: [AppRoute] = []
    /// Общий выбранный период; живёт, пока работает приложение, между запусками не сохраняется.
    @State private var periodSelection: PeriodSelection
    /// ViewModel главного экрана; живёт вместе с RootView, поэтому период и данные не сбрасываются при возврате.
    @State private var homeModel: ExpenseOverviewModel

    /// Создаёт корневой экран и ViewModel главного экрана из зависимостей.
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies // Сохраняем зависимости.
        // Общий период для всех экранов.
        let selection = PeriodSelection()
        _periodSelection = State(initialValue: selection) // Период создаётся один раз.
        _homeModel = State(initialValue: ExpenseOverviewModel( // ViewModel создаётся один раз.
            selection: selection, // Общий период.
            repository: dependencies.overviewRepository, // Сводки из локальной БД.
            changes: dependencies.ledgerChanges // Оповещения об изменениях.
        ))
    }

    /// Содержимое корневого экрана.
    var body: some View {
        NavigationStack(path: $path) { // Нативный стек навигации с управляемым путём.
            HomeView(model: homeModel, selection: periodSelection) { path.append(.category($0)) } // Главный экран.
                .navigationDestination(for: AppRoute.self) { route in // Экраны стека.
                    switch route { // Экран по маршруту.
                    case .category(let category): // Расходы категории.
                        CategoryExpensesView( // Тот же период и слой данных.
                            category: category, // Категория из строки.
                            selection: periodSelection, // Общий период.
                            repository: dependencies.overviewRepository, // Сводки.
                            changes: dependencies.ledgerChanges // Оповещения.
                        )
                    }
                }
        }
        .tint(AppColor.accent) // Акцент для системных элементов.
        .accessibilityIdentifier("root") // Идентификатор для UI-тестов.
    }
}

/// Preview главного экрана с демонстрационными расходами.
#Preview("RootView") {
    PreviewRoot(fixture: .filled) // Полный набор данных.
}

/// Preview главного экрана при крупном размере текста.
#Preview("RootView, AX3") {
    PreviewRoot(fixture: .filled) // Полный набор данных.
        .environment(\.dynamicTypeSize, .accessibility3) // Крупный Dynamic Type.
}

/// Preview пустого текущего месяца.
#Preview("RootView, пустой месяц") {
    PreviewRoot(fixture: .previousMonthOnly) // Расходы только за прошлый месяц.
}

/// Preview без данных.
#Preview("RootView, без данных") {
    PreviewRoot(fixture: nil) // Пустая БД.
}

/// Корневой экран previews: временная БД, наполненная fixture.
private struct PreviewRoot: View {
    /// Набор данных; `nil` — пустая БД.
    let fixture: LedgerFixture?

    /// Зависимости после наполнения БД.
    @State private var dependencies: AppDependencies?

    /// RootView после подготовки данных.
    var body: some View {
        Group { // Подготовка или экран.
            if let dependencies { RootView(dependencies: dependencies) } else { ProgressView() } // Экран или индикатор.
        }
        .task { // Подготовка данных один раз.
            dependencies = try? await AppDependencies.make(mode: .preview, configuration: .preview, fixture: fixture) // Временная БД без сети.
        }
    }
}

/// Зависимости для previews.
extension AppConfiguration {
    /// Конфигурация previews: без адреса API.
    static let preview = AppConfiguration(apiBaseURL: nil, appVersion: "1.0", buildNumber: "1")
}
