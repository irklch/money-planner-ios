// AppMigrationPlan.swift
// План миграций локальной БД между версиями схемы.

// SwiftData нужен для SchemaMigrationPlan и MigrationStage.
import SwiftData

/// План миграций локальной БД.
///
/// V1 → V2 — лёгкая миграция: `AppSettings` не меняется (флаг онбординга и даты сохраняются),
/// добавляются новые сущности. Ошибка миграции пробрасывается из `ModelContainerFactory`:
/// файл БД не удаляется и не пересоздаётся.
nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
    /// Все версии схемы по порядку.
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self] // От старой к новой.
    }

    /// Этапы миграции между версиями.
    static var stages: [MigrationStage] {
        [migrateV1toV2] // Один этап.
    }

    /// V1 → V2: только добавление сущностей, данные настроек переносятся автоматически.
    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
}
