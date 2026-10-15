// MigrationTests.swift
// Миграция реального временного файла БД V1 → V2 и сохранность данных между открытиями.

// Foundation нужен для Date, URL, Data и FileManager.
import Foundation
// SwiftData нужен для Schema, ModelContainer и ModelContext.
import SwiftData
// Testing нужен для @Suite, @Test, #expect и #require.
import Testing
// Доступ к внутренним типам приложения.
@testable import MoneyPlanner

/// Тесты миграции. MainActor: репозиторий настроек и инициализатор хранилища — на MainActor.
@MainActor
@Suite("Migration V1 → V2") // Набор тестов.
struct MigrationTests { // Тесты миграции.
    /// Момент создания настроек в V1.
    private static let createdAt = Date(timeIntervalSince1970: 1_780_000_000)
    /// Момент изменения настроек в V1.
    private static let updatedAt = Date(timeIntervalSince1970: 1_780_086_400)

    /// Временный каталог теста; удаляется в `defer` вызывающего кода.
    private func makeDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "MigrationTests-\(UUID().uuidString)") // Уникальный путь.
    }

    /// Создаёт файл БД первой версии так, как его создавало приложение этапа 1.
    private func makeV1Store(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) // Каталог файла.
        // Схема только первой версии.
        let schema = Schema(versionedSchema: SchemaV1.self)
        // Та же конфигурация, что у ModelContainerFactory этапа 1.
        let configuration = ModelConfiguration("MoneyPlanner", schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        // Контейнер V1 без плана миграций.
        let container = try ModelContainer(for: schema, configurations: configuration)
        // Контекст для записи.
        let context = ModelContext(container)
        // Настройки с пройденным онбордингом.
        let settings = SchemaV1.AppSettings(hasCompletedOnboarding: true, now: Self.createdAt)
        settings.updatedAt = Self.updatedAt // Время изменения отличается от времени создания.
        context.insert(settings) // Запись настроек.
        try context.save() // Файл V1 на диске.
    }

    /// Миграция сохраняет флаг онбординга и обе даты; новые сущности работают.
    @Test func migratesSettingsFromV1File() async throws {
        // Временный каталог.
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // Удаляем после теста.
        // Файл БД.
        let url = directory.appending(path: "MoneyPlanner.store")
        try makeV1Store(at: url) // Файл первой версии.

        // Контейнер V2 с планом миграций.
        let container = try ModelContainerFactory.makePersistent(at: url)
        // Настройки после миграции.
        let settings = try AppSettingsRepository(container: container).load()
        #expect(settings == AppSettingsSnapshot(hasCompletedOnboarding: true, createdAt: Self.createdAt, updatedAt: Self.updatedAt)) // Данные V1 сохранены.
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AppSettings>()) == 1) // Новая запись не создана.

        // Хранилище новых сущностей поверх мигрированной БД.
        let store = LedgerStore(container: container)
        // Сводка после инициализации.
        let summary = try await store.prepare()
        #expect(summary == LedgerSummary(activeCategoryCount: SystemCategory.allCases.count, expenseCount: 0)) // Сущности V2 доступны.
    }

    /// После миграции данные V2 сохраняются между открытиями, настройки не теряются.
    @Test func migratedStoreKeepsDataAcrossReopen() async throws {
        // Временный каталог.
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // Удаляем после теста.
        // Файл БД.
        let url = directory.appending(path: "MoneyPlanner.store")
        try makeV1Store(at: url) // Файл первой версии.

        // UUID расхода из первого открытия.
        let expenseID: UUID
        // UUID категории из первого открытия.
        let categoryID: UUID
        do { // Первое открытие с миграцией.
            // Хранилище первого открытия.
            let store = LedgerStore(container: try ModelContainerFactory.makePersistent(at: url))
            categoryID = try await store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 3)).id // Новая категория.
            expenseID = try await store.createExpense(ExpenseDraft( // Новый расход.
                amount: .api("250.50"), categoryID: categoryID, date: .iso("2024-02-29"), comment: "Капучино" // Поля расхода.
            )).id // UUID созданной записи.
        }

        // Повторно открытая БД.
        let reopened = try ModelContainerFactory.makePersistent(at: url)
        // Хранилище после повторного открытия.
        let store = LedgerStore(container: reopened)
        // Расход после повторного открытия.
        let expense = try #require(try await store.expense(id: expenseID))
        #expect(expense.amount == .api("250.50")) // Сумма.
        #expect(expense.date == .iso("2024-02-29")) // День.
        #expect(expense.comment == "Капучино") // Комментарий.
        #expect(try await store.category(id: categoryID)?.title == .user("Кофе")) // Категория.
        #expect(try AppSettingsRepository(container: reopened).load().hasCompletedOnboarding) // Настройки V1 на месте.
        #expect(try await store.pendingMutations().count == 2) // Outbox сохранён.
    }

    /// Файл, который не открывается, не удаляется и не перезаписывается.
    @Test func unreadableStoreIsNotDeleted() throws {
        // Временный каталог.
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // Удаляем после теста.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) // Каталог файла.
        // Файл БД.
        let url = directory.appending(path: "MoneyPlanner.store")
        // Содержимое, которое не является SQLite.
        let garbage = Data("not a sqlite database".utf8)
        try garbage.write(to: url) // Повреждённый файл.

        #expect(throws: (any Error).self) { try ModelContainerFactory.makePersistent(at: url) } // Ошибка открытия пробрасывается.
        #expect(try Data(contentsOf: url) == garbage) // Файл не удалён и не перезаписан.
    }
}
