// AppSettingsRepository.swift
// Чтение и запись настроек приложения (`app_settings`) в SwiftData.
// Репозиторий работает в собственном контексте без автосохранения: изменения записываются
// только явным сохранением, а при ошибке сохранения откатываются.

import Foundation
import SwiftData

/// Снимок настроек для UI и ViewModel. Не зависит от SwiftData.
nonisolated struct AppSettingsSnapshot: Sendable, Equatable {
    /// Пользователь прошёл онбординг.
    var hasCompletedOnboarding: Bool
    /// Момент создания записи настроек (первый запуск).
    let createdAt: Date
    /// Момент последнего сохранённого изменения настроек.
    let updatedAt: Date
}

/// Чтение и запись настроек приложения.
protocol AppSettingsStoring {
    /// Возвращает настройки, создавая запись по умолчанию при первом обращении.
    func load() throws -> AppSettingsSnapshot
    /// Сохраняет флаг онбординга.
    func setOnboardingCompleted(_ completed: Bool) throws -> AppSettingsSnapshot
}

/// Хранилище настроек в SwiftData.
///
/// Использует отдельный `ModelContext` с выключенным автосохранением, а не `mainContext`:
/// - запись происходит только в `commit()`;
/// - при ошибке сохранения `rollback()` отбрасывает несохранённые изменения этого контекста,
///   и следующее чтение возвращает последнее сохранённое состояние;
/// - откат не затрагивает другие контексты контейнера (например, `mainContext` для `@Query`).
///
/// Репозиторий изолирован на MainActor (настройки — одна маленькая запись, которую читает UI).
/// Тяжёлые операции (импорт, sync) будут выполняться в отдельном `@ModelActor`.
final class AppSettingsRepository: AppSettingsStoring {
    /// Операция сохранения контекста. В production — `ModelContext.save()`;
    /// тесты подменяют её, чтобы воспроизвести ошибку записи.
    typealias SaveOperation = (ModelContext) throws -> Void

    /// Контейнер БД. Контекст не удерживает контейнер, поэтому репозиторий хранит ссылку сам.
    private let container: ModelContainer
    /// Собственный контекст репозитория с выключенным автосохранением.
    private let context: ModelContext
    /// Источник текущего времени для `createdAt` и `updatedAt`.
    private let now: () -> Date
    /// Операция сохранения контекста (точка подмены для тестов).
    private let save: SaveOperation

    /// Создаёт репозиторий с обычным сохранением контекста.
    /// - Parameters:
    ///   - container: контейнер БД приложения или тестов.
    ///   - now: источник текущего времени.
    convenience init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.init(container: container, now: now, save: { try $0.save() })
    }

    /// Создаёт репозиторий с заданной операцией сохранения. Используется тестами.
    /// - Parameters:
    ///   - container: контейнер БД.
    ///   - now: источник текущего времени.
    ///   - save: операция сохранения контекста.
    init(container: ModelContainer, now: @escaping () -> Date, save: @escaping SaveOperation) {
        self.container = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.context = context
        self.now = now
        self.save = save
    }

    /// Возвращает сохранённые настройки; при первом обращении создаёт и сохраняет запись по умолчанию.
    /// - Throws: ошибку чтения или сохранения. При ошибке сохранения созданная запись откатывается.
    func load() throws -> AppSettingsSnapshot {
        snapshot(of: try fetchOrCreate())
    }

    /// Сохраняет флаг онбординга и время изменения.
    /// - Throws: ошибку чтения или сохранения. При ошибке сохранения изменения откатываются,
    ///   и в контексте остаётся последнее сохранённое состояние.
    func setOnboardingCompleted(_ completed: Bool) throws -> AppSettingsSnapshot {
        let settings = try fetchOrCreate()
        settings.hasCompletedOnboarding = completed
        settings.updatedAt = now()
        try commit()
        return snapshot(of: settings)
    }

    /// Находит единственную запись настроек или создаёт и сохраняет запись по умолчанию.
    private func fetchOrCreate() throws -> AppSettings {
        // Ключ единственной записи; локальная константа нужна для `#Predicate`.
        let key = AppSettings.singletonKey
        // Запрос записи настроек по ключу.
        var descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        // Новая запись настроек по умолчанию.
        let settings = AppSettings(now: now())
        context.insert(settings)
        try commit()
        return settings
    }

    /// Явно сохраняет изменения контекста. При ошибке откатывает их и пробрасывает исходную ошибку.
    private func commit() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Преобразует модель SwiftData в независимый снимок.
    private func snapshot(of settings: AppSettings) -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            createdAt: settings.createdAt,
            updatedAt: settings.updatedAt
        )
    }
}
