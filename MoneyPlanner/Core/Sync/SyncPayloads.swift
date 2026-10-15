// SyncPayloads.swift
// Сетевые DTO payload мутаций sync (`contract/openapi.yaml`: ExpensePayload, CategoryPayload,
// DayMarkPayload) и Sendable-снимок мутации outbox. SyncEngine и запросы push/pull — следующий этап.

// Foundation нужен для UUID, Date, Data и JSONEncoder.
import Foundation

/// Тип сущности sync (`EntityType` контракта).
nonisolated enum SyncEntityType: String, Sendable, Codable {
    /// Расход.
    case expense
    /// Категория.
    case category
    /// Отметка «День без расходов».
    case dayMark = "day_mark"
}

/// Операция мутации (`op` контракта).
nonisolated enum SyncOperation: String, Sendable, Codable {
    /// Создание или изменение.
    case upsert
    /// Удаление (только расходы; категории и отметки не удаляются).
    case delete
}

/// Версия формата payload (`schemaVersion`); сервер знает `SYNC_KNOWN_SCHEMA_VERSIONS = [1]`.
nonisolated enum SyncSchema {
    /// Текущая версия формата payload.
    static let version = 1
}

/// `ExpensePayload` контракта.
nonisolated struct ExpensePayloadDTO: Codable, Sendable, Equatable {
    /// Сумма decimal-строкой ровно с 2 знаками: `"250.50"`.
    let amount: String
    /// UUID категории в нижнем регистре.
    let categoryId: String
    /// Календарный день `YYYY-MM-DD`.
    let date: String
    /// Нормализованный комментарий; `nil` не кодируется.
    let comment: String?
}

/// `UserCategoryPayload` или `SystemCategoryPayload` контракта (дискриминатор `kind`).
nonisolated struct CategoryPayloadDTO: Codable, Sendable, Equatable {
    /// `user` или `system`.
    let kind: String
    /// Название (только `user`).
    let name: String?
    /// Эмодзи (только `user`).
    let emoji: String?
    /// Индекс цвета (только `user`).
    let colorIndex: Int?
    /// Порядок (только `user`, необязательный).
    let sortOrder: Int?
    /// Категория архивирована.
    let isArchived: Bool
}

/// `DayMarkPayload` контракта.
nonisolated struct DayMarkPayloadDTO: Codable, Sendable, Equatable {
    /// Календарный день `YYYY-MM-DD`.
    let date: String
    /// Отметка поставлена.
    let isMarked: Bool
}

/// Кодирование payload в JSON outbox.
nonisolated enum SyncPayloadCoder {
    /// Кодирует payload с упорядоченными ключами: одинаковое тело даёт одинаковые байты.
    static func encode<Payload: Encodable>(_ payload: Payload) throws -> Data {
        // Кодировщик JSON без экранирования `/`.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes] // Стабильный порядок ключей, `/` без экранирования.
        return try encoder.encode(payload) // JSON payload.
    }

    /// Декодирует payload через `JSONDecoder` (а не `JSONSerialization`, который теряет ведущий U+FEFF).
    static func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        try JSONDecoder().decode(type, from: data) // Значение payload.
    }
}

/// Снимок мутации outbox для будущего SyncEngine и тестов.
nonisolated struct OutboxMutationSnapshot: Sendable, Equatable {
    /// Ключ идемпотентности.
    let mutationID: UUID
    /// Порядок отправки.
    let sequence: Int64
    /// Тип сущности.
    let entityType: SyncEntityType
    /// UUID записи.
    let entityID: UUID
    /// Операция.
    let operation: SyncOperation
    /// Базовая серверная версия.
    let baseVersion: Int64
    /// `createdAt` записи.
    let entityCreatedAt: Date
    /// `updatedAt` записи.
    let updatedAt: Date
    /// `deletedAt` для удаления.
    let deletedAt: Date?
    /// Версия формата payload.
    let schemaVersion: Int
    /// JSON payload; `nil` для удаления.
    let payload: Data?
}
