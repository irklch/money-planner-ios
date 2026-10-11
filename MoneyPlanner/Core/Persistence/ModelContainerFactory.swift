import Foundation
import SwiftData

/// Создаёт `ModelContainer` для приложения, previews и тестов.
///
/// CloudKit отключён явно: синхронизация идёт через собственный бэкенд.
nonisolated enum ModelContainerFactory {
    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// Расположение пользовательской БД.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "MoneyPlanner.store")
    }

    /// Постоянное хранилище. Ошибка открытия пробрасывается: БД не удаляется и не подменяется.
    static func makePersistent(at url: URL = defaultStoreURL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(
            "MoneyPlanner",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
    }

    /// Временное хранилище в памяти для previews, UI- и unit-тестов.
    /// Каждый вызов создаёт изолированную БД.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "InMemory-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
    }
}
