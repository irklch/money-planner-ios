// SchemaV2.swift
// Вторая версия локальной схемы: настройки, категории, расходы, отметки дня и outbox мутаций sync.

// Foundation нужен для UUID, Date и Data.
import Foundation
// SwiftData нужен для моделей и версионированной схемы.
import SwiftData

/// Вторая версия локальной схемы.
///
/// `AppSettings` перенесена из `SchemaV1` без изменений; остальные сущности добавлены.
/// Метаданные sync повторяют общие поля записи контракта (архитектура §8.1):
/// клиентский UUID, `createdAt`/`updatedAt` (часы устройства), `deletedAt` (tombstone расхода)
/// и `serverVersion` — последняя известная серверная версия (0 — запись на сервер ещё не попадала).
/// Связи между сущностями хранятся UUID, без SwiftData-relationship: на клиенте нет FK
/// (план §3.2), каскадного удаления нет, расход сохраняет UUID архивной категории.
nonisolated enum SchemaV2: VersionedSchema {
    /// Номер версии схемы.
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) } // Версия 2.0.0.

    /// Модели, входящие в эту версию схемы.
    static var models: [any PersistentModel.Type] {
        [AppSettings.self, Category.self, Expense.self, DayMark.self, OutboxMutation.self] // Все сущности V2.
    }

    /// Настройки приложения на устройстве (`app_settings`). Не синхронизируются. Совпадает с V1.
    @Model
    final class AppSettings { // Модель SwiftData.
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

    /// Категория расходов (`category` в sync). Не удаляется, а архивируется.
    @Model
    final class Category { // Модель SwiftData.
        /// Стабильный UUID: из реестра для системных, случайный UUID клиента для пользовательских.
        @Attribute(.unique) var id: UUID
        /// Вид категории: `system` или `user` (`CategoryKind.rawValue`). Не меняется.
        var kindRaw: String
        /// Название пользовательской категории как ввёл пользователь; у системной — `nil`.
        var name: String?
        /// Эмодзи пользовательской категории; у системной — `nil` (берётся из реестра).
        var emoji: String?
        /// Индекс цвета пользовательской категории; у системной — `nil` (берётся из реестра).
        var colorIndex: Int?
        /// Порядок в списке категорий.
        var sortOrder: Int
        /// Категория архивирована.
        var isArchived: Bool
        /// Момент создания записи (часы устройства).
        var createdAt: Date
        /// Момент последнего изменения (часы устройства).
        var updatedAt: Date
        /// Последняя известная серверная версия; 0 — на сервер ещё не отправлялась.
        var serverVersion: Int64

        /// Создаёт категорию.
        init(
            id: UUID, // Стабильный UUID.
            kind: CategoryKind, // Вид категории.
            name: String?, // Название пользовательской категории.
            emoji: String?, // Эмодзи пользовательской категории.
            colorIndex: Int?, // Индекс цвета пользовательской категории.
            sortOrder: Int, // Порядок в списке.
            now: Date // Момент создания.
        ) {
            self.id = id // UUID.
            self.kindRaw = kind.rawValue // Вид как строка контракта.
            self.name = name // Название.
            self.emoji = emoji // Эмодзи.
            self.colorIndex = colorIndex // Цвет.
            self.sortOrder = sortOrder // Порядок.
            self.isArchived = false // Новая категория активна.
            self.createdAt = now // Время создания.
            self.updatedAt = now // Время изменения совпадает со временем создания.
            self.serverVersion = 0 // На сервере записи ещё нет.
        }
    }

    /// Расход (`expense` в sync): ручной или сохранённый из выписки — одна сущность.
    @Model
    final class Expense { // Модель SwiftData.
        #Index<Expense>([\.dateKey], [\.categoryID]) // Индексы для выборки по периоду и категории.

        /// Стабильный UUID, созданный клиентом.
        @Attribute(.unique) var id: UUID
        /// Сумма в копейках (1 … 99 999 999 999).
        var amountMinorUnits: Int64
        /// UUID категории (без relationship: связь переживает архивирование и неполную загрузку).
        var categoryID: UUID
        /// Календарный день как `YYYYMMDD` (`CalendarDate.storageKey`), не момент времени.
        var dateKey: Int
        /// Нормализованный комментарий (≤ 200 Unicode scalar values); `nil` — без комментария.
        var comment: String?
        /// Момент создания (часы устройства).
        var createdAt: Date
        /// Момент последнего изменения (часы устройства).
        var updatedAt: Date
        /// Момент удаления; не `nil` — tombstone, запись скрыта из истории, но хранится для sync.
        var deletedAt: Date?
        /// Последняя известная серверная версия; 0 — на сервер ещё не отправлялась.
        var serverVersion: Int64

        /// Создаёт расход.
        init(id: UUID, amountMinorUnits: Int64, categoryID: UUID, dateKey: Int, comment: String?, now: Date) {
            self.id = id // UUID.
            self.amountMinorUnits = amountMinorUnits // Сумма.
            self.categoryID = categoryID // Категория.
            self.dateKey = dateKey // День.
            self.comment = comment // Комментарий.
            self.createdAt = now // Время создания.
            self.updatedAt = now // Время изменения совпадает со временем создания.
            self.deletedAt = nil // Живая запись.
            self.serverVersion = 0 // На сервере записи ещё нет.
        }
    }

    /// Отметка «День без расходов» (`day_mark` в sync). Не удаляется: снятие — `isMarked = false`.
    @Model
    final class DayMark { // Модель SwiftData.
        /// `UUIDv5(NS_DAY_MARK, "YYYY-MM-DD")` — общий для всех устройств.
        @Attribute(.unique) var id: UUID
        /// Календарный день как `YYYYMMDD`.
        var dateKey: Int
        /// Отметка поставлена.
        var isMarked: Bool
        /// Момент создания (часы устройства).
        var createdAt: Date
        /// Момент последнего изменения (часы устройства).
        var updatedAt: Date
        /// Последняя известная серверная версия; 0 — на сервер ещё не отправлялась.
        var serverVersion: Int64

        /// Создаёт отметку дня.
        init(id: UUID, dateKey: Int, isMarked: Bool, now: Date) {
            self.id = id // UUIDv5 по дате.
            self.dateKey = dateKey // День.
            self.isMarked = isMarked // Состояние.
            self.createdAt = now // Время создания.
            self.updatedAt = now // Время изменения совпадает со временем создания.
            self.serverVersion = 0 // На сервере записи ещё нет.
        }
    }

    /// Неотправленная мутация sync (outbox). Пишется в одной транзакции с изменением данных.
    ///
    /// Поля повторяют конверт `MutationBase` контракта. Тело (`payload`) фиксируется при записи:
    /// повтор с тем же `mutationId`, но другим телом сервер отклонил бы как `mutation_id_reused`.
    /// Мутация удаляется только после ответа сервера (этап sync).
    @Model
    final class OutboxMutation { // Модель SwiftData.
        #Index<OutboxMutation>([\.sequence]) // Индекс для чтения outbox по порядку.

        /// Ключ идемпотентности мутации (`mutationId`).
        @Attribute(.unique) var mutationID: UUID
        /// Порядковый номер в outbox: порядок отправки (категории раньше расходов, которые на них ссылаются).
        @Attribute(.unique) var sequence: Int64
        /// Тип сущности: `expense`, `category`, `day_mark` (`SyncEntityType.rawValue`).
        var entityTypeRaw: String
        /// UUID изменённой записи (`entityId`).
        var entityID: UUID
        /// Операция: `upsert` или `delete` (`SyncOperation.rawValue`).
        var opRaw: String
        /// Серверная версия, на которой основана правка; 0 — создание. Перебазируется клиентом после `applied`.
        var baseVersion: Int64
        /// `createdAt` записи.
        var entityCreatedAt: Date
        /// `updatedAt` записи на момент правки.
        var updatedAt: Date
        /// `deletedAt` для удаления; иначе `nil`.
        var deletedAt: Date?
        /// Версия формата payload (`schemaVersion`), сейчас 1.
        var schemaVersion: Int
        /// JSON payload мутации; `nil` для удаления (tombstone).
        var payload: Data?

        /// Создаёт мутацию.
        init(
            mutationID: UUID, // Ключ идемпотентности.
            sequence: Int64, // Порядок в outbox.
            entityType: SyncEntityType, // Тип сущности.
            entityID: UUID, // UUID записи.
            operation: SyncOperation, // Операция.
            baseVersion: Int64, // Базовая серверная версия.
            entityCreatedAt: Date, // createdAt записи.
            updatedAt: Date, // updatedAt записи.
            deletedAt: Date?, // deletedAt для удаления.
            schemaVersion: Int, // Версия формата payload.
            payload: Data? // Тело мутации.
        ) {
            self.mutationID = mutationID // Ключ идемпотентности.
            self.sequence = sequence // Порядок.
            self.entityTypeRaw = entityType.rawValue // Тип сущности строкой контракта.
            self.entityID = entityID // UUID записи.
            self.opRaw = operation.rawValue // Операция строкой контракта.
            self.baseVersion = baseVersion // Базовая версия.
            self.entityCreatedAt = entityCreatedAt // createdAt.
            self.updatedAt = updatedAt // updatedAt.
            self.deletedAt = deletedAt // deletedAt.
            self.schemaVersion = schemaVersion // Версия формата.
            self.payload = payload // Тело.
        }
    }
}

/// Текущие версии моделей: код приложения ссылается на них без номера схемы.
typealias AppSettings = SchemaV2.AppSettings
/// Текущая модель категории.
typealias Category = SchemaV2.Category
/// Текущая модель расхода.
typealias Expense = SchemaV2.Expense
/// Текущая модель отметки дня.
typealias DayMark = SchemaV2.DayMark
/// Текущая модель мутации outbox.
typealias OutboxMutation = SchemaV2.OutboxMutation
