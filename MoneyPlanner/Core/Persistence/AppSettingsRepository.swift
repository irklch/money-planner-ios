import Foundation
import SwiftData

/// Снимок настроек для UI и ViewModel. Не зависит от SwiftData.
nonisolated struct AppSettingsSnapshot: Sendable, Equatable {
    var hasCompletedOnboarding: Bool
    let createdAt: Date
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
/// Работает в главном контексте контейнера: настройки — одна маленькая запись, которую читает UI.
/// Тяжёлые операции (импорт, sync) будут выполняться в отдельном `@ModelActor`.
final class AppSettingsRepository: AppSettingsStoring {
    /// Контекст не удерживает контейнер, поэтому репозиторий хранит ссылку на него сам.
    private let container: ModelContainer
    private let context: ModelContext
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.container = container
        self.context = container.mainContext
        self.now = now
    }

    func load() throws -> AppSettingsSnapshot {
        try snapshot(of: fetchOrCreate())
    }

    func setOnboardingCompleted(_ completed: Bool) throws -> AppSettingsSnapshot {
        let settings = try fetchOrCreate()
        settings.hasCompletedOnboarding = completed
        settings.updatedAt = now()
        try context.save()
        return snapshot(of: settings)
    }

    private func fetchOrCreate() throws -> AppSettings {
        let key = AppSettings.singletonKey
        var descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings(now: now())
        context.insert(settings)
        try context.save()
        return settings
    }

    private func snapshot(of settings: AppSettings) -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            createdAt: settings.createdAt,
            updatedAt: settings.updatedAt
        )
    }
}
