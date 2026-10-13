// AppSettingsRepositoryTests.swift
// Тесты хранилища настроек: сохранение между открытиями БД, изоляция тестовых хранилищ
// и откат изменений ModelContext при ошибке сохранения.

import Foundation
import SwiftData
import Testing
@testable import MoneyPlanner

@MainActor
@Suite("AppSettingsRepository")
struct AppSettingsRepositoryTests {
    /// Момент первой операции в тестах с управляемым временем.
    private static let firstDate = Date(timeIntervalSince1970: 1_790_000_000)
    /// Момент второй операции.
    private static let secondDate = Date(timeIntervalSince1970: 1_790_000_600)
    /// Момент третьей операции.
    private static let thirdDate = Date(timeIntervalSince1970: 1_790_001_200)

    // MARK: - Сохранение и изоляция

    /// Настройки, сохранённые во временной файловой БД, читаются после её повторного открытия.
    @Test func settingsSurviveReopeningTemporaryStore() throws {
        // Временный каталог теста; удаляется после проверки.
        let directory = URL.temporaryDirectory.appending(path: "AppSettingsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Файл временной БД.
        let storeURL = directory.appending(path: "Test.store")

        do {
            // Первое открытие БД: создание и изменение настроек.
            let container = try ModelContainerFactory.makePersistent(at: storeURL)
            // Репозиторий первого открытия.
            let repository = AppSettingsRepository(container: container, now: { Self.firstDate })
            #expect(try repository.load().hasCompletedOnboarding == false)
            _ = try repository.setOnboardingCompleted(true)
        }

        // Повторно открытая БД.
        let reopened = try ModelContainerFactory.makePersistent(at: storeURL)
        // Настройки, прочитанные после повторного открытия.
        let settings = try AppSettingsRepository(container: reopened).load()

        #expect(settings.hasCompletedOnboarding)
        #expect(settings.createdAt == Self.firstDate)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    /// Повторное чтение не создаёт вторую запись настроек.
    @Test func loadCreatesSingleRecord() throws {
        // Изолированная БД в памяти.
        let container = try ModelContainerFactory.makeInMemory()
        // Проверяемый репозиторий.
        let repository = AppSettingsRepository(container: container)

        // Результат первого чтения (создание записи).
        let first = try repository.load()
        // Результат второго чтения.
        let second = try repository.load()

        #expect(first == second)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    /// Хранилища в памяти не видят данных друг друга и не используют файл пользовательской БД.
    @Test func inMemoryStoresAreIsolated() throws {
        // Первая БД, в которую записываются настройки.
        let first = try ModelContainerFactory.makeInMemory()
        // Вторая БД, которая должна остаться пустой.
        let second = try ModelContainerFactory.makeInMemory()

        _ = try AppSettingsRepository(container: first).setOnboardingCompleted(true)

        #expect(try AppSettingsRepository(container: second).load().hasCompletedOnboarding == false)
        // Конфигурация первой БД.
        let configuration = try #require(first.configurations.first)
        #expect(configuration.isStoredInMemoryOnly)
        #expect(configuration.url != ModelContainerFactory.defaultStoreURL)
        #expect(configuration.cloudKitContainerIdentifier == nil)
    }

    /// Процесс unit-тестов не открывает пользовательскую БД и не создаёт сетевых сервисов.
    @Test func testProcessNeverUsesUserStore() throws {
        // Режим запуска текущего процесса.
        let mode = LaunchMode.detect()

        #expect(mode == .unitTesting)
        #expect(mode.usesPersistentStore == false)
        #expect(mode.allowsNetwork == false)

        // Зависимости, собранные так же, как при запуске приложения.
        let dependencies = try AppDependencies.make(
            mode: mode,
            configuration: AppConfiguration(apiBaseURL: URL(string: "https://example.test"), appVersion: "1", buildNumber: "1")
        )
        #expect(dependencies.modelContainer.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(dependencies.healthService == nil)
    }

    // MARK: - Ошибка сохранения

    /// После неудачного изменения чтение возвращает прежнее сохранённое значение и `updatedAt`.
    @Test func failedUpdateKeepsLastSavedState() throws {
        // Изолированная БД в памяти.
        let container = try ModelContainerFactory.makeInMemory()
        // Управляемое время.
        let clock = TestClock(Self.firstDate)
        // Управляемое сохранение.
        let saver = ControlledSave()
        // Проверяемый репозиторий.
        let repository = AppSettingsRepository(container: container, now: { clock.now }, save: saver.save)
        // Последнее успешно сохранённое состояние.
        let saved = try repository.setOnboardingCompleted(true)

        clock.now = Self.secondDate
        saver.failsNextSave = true
        #expect(throws: SimulatedSaveError.self) {
            try repository.setOnboardingCompleted(false)
        }

        // Контекст репозитория без несохранённых изменений.
        let context = try #require(saver.lastContext)
        #expect(context.hasChanges == false)
        #expect(try repository.load() == saved)
        #expect(saved.hasCompletedOnboarding)
        #expect(saved.updatedAt == Self.firstDate)
        // Состояние в хранилище, прочитанное независимым контекстом.
        let stored = try fetchSettings(in: ModelContext(container))
        #expect(stored?.hasCompletedOnboarding == true)
        #expect(stored?.updatedAt == Self.firstDate)
    }

    /// После неудачного создания в контексте и в хранилище не остаётся незаписанной записи.
    @Test func failedCreationLeavesNoPendingRecord() throws {
        // Изолированная БД в памяти.
        let container = try ModelContainerFactory.makeInMemory()
        // Сохранение, которое завершится ошибкой.
        let saver = ControlledSave()
        saver.failsNextSave = true
        // Проверяемый репозиторий.
        let repository = AppSettingsRepository(container: container, now: { Self.firstDate }, save: saver.save)

        #expect(throws: SimulatedSaveError.self) {
            try repository.load()
        }

        // Контекст репозитория после отката.
        let context = try #require(saver.lastContext)
        #expect(context.hasChanges == false)
        #expect(context.insertedModelsArray.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AppSettings>()) == 0)
    }

    /// После ошибок сохранения следующие успешные операции создают и изменяют настройки корректно.
    @Test func operationsSucceedAfterFailure() throws {
        // Изолированная БД в памяти.
        let container = try ModelContainerFactory.makeInMemory()
        // Управляемое время.
        let clock = TestClock(Self.firstDate)
        // Управляемое сохранение.
        let saver = ControlledSave()
        // Проверяемый репозиторий.
        let repository = AppSettingsRepository(container: container, now: { clock.now }, save: saver.save)

        saver.failsNextSave = true
        #expect(throws: SimulatedSaveError.self) { try repository.load() }

        clock.now = Self.secondDate
        // Настройки, созданные успешным чтением после ошибки.
        let created = try repository.load()
        #expect(created == AppSettingsSnapshot(hasCompletedOnboarding: false, createdAt: Self.secondDate, updatedAt: Self.secondDate))

        saver.failsNextSave = true
        #expect(throws: SimulatedSaveError.self) { try repository.setOnboardingCompleted(true) }

        clock.now = Self.thirdDate
        // Результат успешного изменения после ошибки.
        let updated = try repository.setOnboardingCompleted(true)
        #expect(updated == AppSettingsSnapshot(hasCompletedOnboarding: true, createdAt: Self.secondDate, updatedAt: Self.thirdDate))
        #expect(try repository.load() == updated)

        // Состояние в хранилище, прочитанное независимым контекстом.
        let independent = ModelContext(container)
        #expect(try independent.fetchCount(FetchDescriptor<AppSettings>()) == 1)
        #expect(try fetchSettings(in: independent)?.updatedAt == Self.thirdDate)
        #expect(saver.failedSaves == 2)
    }

    /// Откат в контексте репозитория не отбрасывает несохранённые изменения другого контекста.
    @Test func rollbackDoesNotAffectOtherContext() throws {
        // Изолированная БД в памяти.
        let container = try ModelContainerFactory.makeInMemory()
        // Управляемое сохранение.
        let saver = ControlledSave()
        // Проверяемый репозиторий с сохранённой записью настроек.
        let repository = AppSettingsRepository(container: container, now: { Self.firstDate }, save: saver.save)
        _ = try repository.load()

        // Другой контекст с несохранёнными изменениями той же записи.
        let other = ModelContext(container)
        other.autosaveEnabled = false
        // Та же запись настроек, загруженная другим контекстом.
        let otherSettings = try #require(try fetchSettings(in: other))
        otherSettings.hasCompletedOnboarding = true
        otherSettings.updatedAt = Self.thirdDate

        saver.failsNextSave = true
        #expect(throws: SimulatedSaveError.self) {
            try repository.setOnboardingCompleted(false)
        }

        #expect(other.hasChanges)
        #expect(otherSettings.hasCompletedOnboarding)
        #expect(otherSettings.updatedAt == Self.thirdDate)
        #expect(saver.lastContext?.hasChanges == false)

        // Изменения другого контекста по-прежнему можно сохранить.
        try other.save()
        #expect(try fetchSettings(in: ModelContext(container))?.updatedAt == Self.thirdDate)
    }

    // MARK: - Helpers

    /// Читает запись настроек в заданном контексте.
    private func fetchSettings(in context: ModelContext) throws -> AppSettings? {
        // Запрос не более одной записи настроек.
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// Ошибка, которой тест имитирует сбой записи БД.
private struct SimulatedSaveError: Error {}

/// Управляемый источник времени.
@MainActor
private final class TestClock {
    /// Время, которое получит репозиторий.
    var now: Date

    /// Создаёт часы с начальным временем.
    init(_ now: Date) {
        self.now = now
    }
}

/// Операция сохранения для тестов: настоящий `ModelContext.save()` или ошибка по требованию.
///
/// Ошибка выбрасывается до записи, поэтому несохранённые изменения остаются в контексте,
/// и тест проверяет реальный откат через `ModelContext.rollback()` в репозитории.
@MainActor
private final class ControlledSave {
    /// Следующее сохранение завершится ошибкой; флаг сбрасывается после неё.
    var failsNextSave = false
    /// Число имитированных ошибок.
    private(set) var failedSaves = 0
    /// Контекст, который репозиторий передал в последнее сохранение.
    private(set) var lastContext: ModelContext?

    /// Сохраняет контекст или выбрасывает `SimulatedSaveError`.
    func save(_ context: ModelContext) throws {
        lastContext = context
        if failsNextSave {
            failsNextSave = false
            failedSaves += 1
            throw SimulatedSaveError()
        }
        try context.save()
    }
}
