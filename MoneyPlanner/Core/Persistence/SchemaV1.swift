import Foundation
import SwiftData

/// Первая версия локальной схемы.
///
/// Новые сущности и изменения полей добавляются в следующую версию (`SchemaV2`)
/// с этапом миграции в `AppMigrationPlan`, а не правкой этой схемы.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [AppSettings.self]
    }

    /// Настройки приложения на устройстве (`app_settings`).
    ///
    /// Одна запись на устройство. Не синхронизируется с сервером: по архитектуре backend
    /// `app_settings` остаются только на устройстве. Сюда попадают общие настройки устройства
    /// и, позже, настройки, связанные с аккаунтом.
    @Model
    final class AppSettings {
        /// Ключ единственной записи.
        static let singletonKey = "device"

        @Attribute(.unique) var key: String
        /// Пользователь прошёл онбординг.
        var hasCompletedOnboarding: Bool
        var createdAt: Date
        var updatedAt: Date

        init(key: String = AppSettings.singletonKey, hasCompletedOnboarding: Bool = false, now: Date = .now) {
            self.key = key
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.createdAt = now
            self.updatedAt = now
        }
    }
}

/// Текущие версии моделей.
typealias AppSettings = SchemaV1.AppSettings

/// План миграций локальной БД. Пока одна версия и нет этапов.
nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
