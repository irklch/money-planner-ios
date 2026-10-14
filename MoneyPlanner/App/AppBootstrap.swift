// AppBootstrap.swift
// Запуск приложения: открытие БД, сборка зависимостей и состояние ошибки открытия.

// Foundation нужен для Bundle.
import Foundation
// Observation нужен для макроса @Observable.
import Observation
// os нужен для системного логгера Logger.
import os

/// Запуск приложения: открытие БД и сборка зависимостей.
@Observable
final class AppBootstrap {
    /// Этап запуска.
    enum State {
        /// БД ещё открывается.
        case loading
        /// Зависимости собраны, можно показывать интерфейс.
        case ready(AppDependencies)
        /// БД не открылась; пользователь видит экран с «Повторить».
        case failed
    }

    /// Текущий этап запуска; меняется только внутри класса.
    private(set) var state: State = .loading

    /// Операция сборки зависимостей; внедряется для previews и тестов.
    private let makeDependencies: () throws -> AppDependencies
    /// Логгер запуска (без пользовательских данных).
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MoneyPlanner", category: "bootstrap")

    /// Создаёт запуск с заданной операцией сборки зависимостей.
    init(makeDependencies: @escaping () throws -> AppDependencies) {
        self.makeDependencies = makeDependencies // Сохраняем операцию сборки.
    }

    /// Создаёт запуск для текущего процесса: режим и конфигурация определяются автоматически.
    convenience init(mode: LaunchMode = .detect(), configuration: AppConfiguration = .current()) {
        self.init { try AppDependencies.make(mode: mode, configuration: configuration) } // Стандартная сборка зависимостей.
    }

    /// Открывает БД. При ошибке файл БД не удаляется и не подменяется временным хранилищем.
    func start() {
        do {
            state = .ready(try makeDependencies()) // Собираем зависимости и переходим к интерфейсу.
        } catch {
            logger.error("Persistent store failed to open: \(String(describing: type(of: error)), privacy: .public)") // Логируем только тип ошибки.
            state = .failed // Показываем экран ошибки с повторной попыткой.
        }
    }
}
