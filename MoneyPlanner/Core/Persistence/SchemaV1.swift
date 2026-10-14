// SchemaV1.swift
// Первая версия локальной схемы SwiftData и план миграций.

// Foundation нужен для Date.
import Foundation
// SwiftData нужен для моделей, схем и миграций.
import SwiftData

/// Первая версия локальной схемы.
///
/// Новые сущности и изменения полей добавляются в следующую версию (`SchemaV2`)
/// с этапом миграции в `AppMigrationPlan`, а не правкой этой схемы.
nonisolated enum SchemaV1: VersionedSchema {
    /// Номер версии схемы.
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) } // Версия 1.0.0.

    /// Модели, входящие в эту версию схемы.
    static var models: [any PersistentModel.Type] {
        [AppSettings.self] // Пока только настройки приложения.
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

        /// Ключ записи; уникальность гарантирует одну запись настроек.
        @Attribute(.unique) var key: String
        /// Пользователь прошёл онбординг.
        var hasCompletedOnboarding: Bool
        /// Момент создания записи (первый запуск).
        var createdAt: Date
        /// Момент последнего изменения.
        var updatedAt: Date

        /// Создаёт запись настроек со значениями по умолчанию.
        init(key: String = AppSettings.singletonKey, hasCompletedOnboarding: Bool = false, now: Date = .now) {
            self.key = key // Ключ единственной записи.
            self.hasCompletedOnboarding = hasCompletedOnboarding // По умолчанию онбординг не пройден.
            self.createdAt = now // Время создания.
            self.updatedAt = now // При создании время изменения совпадает со временем создания.
        }
    }
}

/// Текущие версии моделей: код приложения ссылается на них без номера схемы.
typealias AppSettings = SchemaV1.AppSettings

/// План миграций локальной БД. Пока одна версия и нет этапов.
nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
    /// Все версии схемы по порядку.
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self] // Единственная версия.
    }

    /// Этапы миграции между версиями.
    static var stages: [MigrationStage] {
        [] // Этапов нет, пока есть только V1.
    }
}
