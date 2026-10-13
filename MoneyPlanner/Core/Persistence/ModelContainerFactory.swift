// ModelContainerFactory.swift
// Фабрика ModelContainer: постоянное хранилище для приложения и изолированное in-memory для previews и тестов.

// Foundation нужен для URL, FileManager и UUID.
import Foundation
// SwiftData нужен для ModelContainer и ModelConfiguration.
import SwiftData

/// Создаёт `ModelContainer` для приложения, previews и тестов.
///
/// CloudKit отключён явно: синхронизация идёт через собственный бэкенд.
nonisolated enum ModelContainerFactory {
    /// Текущая версионированная схема БД.
    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// Расположение пользовательской БД.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "MoneyPlanner.store") // Файл в Application Support приложения.
    }

    /// Постоянное хранилище. Ошибка открытия пробрасывается: БД не удаляется и не подменяется.
    static func makePersistent(at url: URL = defaultStoreURL) throws -> ModelContainer {
        try FileManager.default.createDirectory( // Каталог может ещё не существовать при первом запуске.
            at: url.deletingLastPathComponent(), // Каталог файла БД.
            withIntermediateDirectories: true // Создаём все недостающие уровни.
        )
        let configuration = ModelConfiguration( // Конфигурация файлового хранилища.
            "MoneyPlanner", // Имя конфигурации.
            schema: schema, // Текущая схема.
            url: url, // Явный путь к файлу БД.
            allowsSave: true, // Хранилище доступно для записи.
            cloudKitDatabase: .none // CloudKit явно отключён.
        )
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration) // Открываем БД с планом миграций.
    }

    /// Временное хранилище в памяти для previews, UI- и unit-тестов.
    /// Каждый вызов создаёт изолированную БД.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration( // Конфигурация хранилища в памяти.
            "InMemory-\(UUID().uuidString)", // Уникальное имя: хранилища разных вызовов не пересекаются.
            schema: schema, // Текущая схема.
            isStoredInMemoryOnly: true, // Данные не пишутся на диск.
            allowsSave: true, // Сохранение разрешено (в память).
            cloudKitDatabase: .none // CloudKit явно отключён.
        )
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration) // Создаём контейнер с планом миграций.
    }
}
