// MoneyPlannerApp.swift
// Точка входа приложения и экран запуска: RootView после открытия БД или состояние ошибки.

// SwiftData нужен для модификатора modelContainer.
import SwiftData
// SwiftUI нужен для App, Scene и View.
import SwiftUI

/// Точка входа приложения.
@main
struct MoneyPlannerApp: App {
    /// Запуск приложения; живёт всё время работы сцены.
    @State private var bootstrap = AppBootstrap()

    /// Главная сцена приложения.
    var body: some Scene {
        WindowGroup { // Окно приложения.
            AppLaunchView(bootstrap: bootstrap) // Экран запуска решает, что показывать.
        }
    }
}

/// Показывает RootView после открытия БД или состояние ошибки с повторной попыткой.
struct AppLaunchView: View {
    /// Состояние запуска приложения.
    let bootstrap: AppBootstrap

    /// Содержимое экрана запуска.
    var body: some View {
        Group { // Общий контейнер для модификатора .task.
            switch bootstrap.state { // Содержимое зависит от этапа запуска.
            case .loading: // БД ещё открывается.
                ProgressView() // Системный индикатор загрузки.
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Индикатор по центру экрана.
                    .background(AppColor.background) // Фон экрана из дизайн-системы.
            case .ready(let dependencies): // Зависимости готовы.
                RootView(dependencies: dependencies) // Корневой экран приложения.
                    .modelContainer(dependencies.modelContainer) // Контейнер БД для @Query в дочерних экранах.
            case .failed: // БД не открылась.
                ErrorStateView( // Общий компонент ошибки.
                    icon: .error, // Иконка ошибки.
                    title: .errorStorageTitle, // «Не удалось открыть данные».
                    message: .errorStorageMessage, // Пояснение и подсказка.
                    retry: bootstrap.start // «Повторить» заново открывает БД.
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Компонент на весь экран.
                .background(AppColor.background) // Фон экрана из дизайн-системы.
            }
        }
        .task { // Запуск при первом появлении экрана.
            if case .loading = bootstrap.state { // Открываем БД только один раз.
                bootstrap.start() // Открытие БД и сборка зависимостей.
            }
        }
    }
}

/// Preview: экран ошибки открытия БД.
#Preview("Ошибка открытия БД") {
    let bootstrap = AppBootstrap { throw CocoaError(.fileReadCorruptFile) } // Сборка, которая всегда завершается ошибкой.
    AppLaunchView(bootstrap: bootstrap) // Экран запуска покажет состояние ошибки.
}
