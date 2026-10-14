import Foundation
import Observation
import os

/// Запуск приложения: открытие БД и сборка зависимостей.
@Observable
final class AppBootstrap {
    enum State {
        case loading
        case ready(AppDependencies)
        case failed
    }

    private(set) var state: State = .loading

    private let makeDependencies: () throws -> AppDependencies
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MoneyPlanner", category: "bootstrap")

    init(makeDependencies: @escaping () throws -> AppDependencies) {
        self.makeDependencies = makeDependencies
    }

    convenience init(mode: LaunchMode = .detect(), configuration: AppConfiguration = .current()) {
        self.init { try AppDependencies.make(mode: mode, configuration: configuration) }
    }

    /// Открывает БД. При ошибке файл БД не удаляется и не подменяется временным хранилищем.
    func start() {
        do {
            state = .ready(try makeDependencies())
        } catch {
            logger.error("Persistent store failed to open: \(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
    }
}
