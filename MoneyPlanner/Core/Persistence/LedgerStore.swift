// LedgerStore.swift
// Хранилище расходов, категорий и отметок дня в SwiftData на отдельном ModelActor.
// Каждая операция — одна синхронная транзакция: данные и мутация outbox сохраняются вместе
// или откатываются вместе.

// Foundation нужен для UUID, Date и TimeZone.
import Foundation
// SwiftData нужен для ModelActor, ModelContext и FetchDescriptor.
import SwiftData

/// Хранилище данных пользователя на устройстве.
///
/// - Работает в собственном `ModelContext` с выключенным автосохранением; запись — только в `write`.
/// - Изменение записи и регистрация мутации outbox сохраняются одним `save()`. При ошибке
///   `rollback()` отбрасывает все изменения транзакции, ошибка пробрасывается без изменений.
/// - Внутри транзакции нет `await`: актор выполняет её целиком, параллельные вызовы ждут.
///   Поэтому системные категории не создаются дважды.
/// - Один экземпляр на контейнер создаётся в `AppDependencies`. Инициализатор при изоляции модуля
///   по умолчанию выполняется на MainActor; методы — на исполнителе актора.
actor LedgerStore: ModelActor, CategoryRepository, ExpenseRepository, DayMarkRepository, LedgerSummaryProviding {
    /// Операция сохранения контекста. В production — `ModelContext.save()`;
    /// тесты подменяют её, чтобы воспроизвести ошибку записи.
    typealias SaveOperation = @Sendable (ModelContext) throws -> Void

    /// Исполнитель актора с собственным контекстом.
    nonisolated let modelExecutor: any ModelExecutor
    /// Контейнер БД.
    nonisolated let modelContainer: ModelContainer

    /// Источник текущего момента для `createdAt`/`updatedAt`/`deletedAt`.
    private let now: @Sendable () -> Date
    /// Часовой пояс, в котором определяется «сегодня».
    private let timeZone: @Sendable () -> TimeZone
    /// Операция сохранения контекста (точка подмены для тестов).
    private let save: SaveOperation
    /// Системные категории уже проверены и сохранены в этом хранилище.
    private var systemCategoriesReady = false

    /// Создаёт хранилище поверх контейнера.
    /// - Parameters:
    ///   - container: контейнер БД приложения или тестов.
    ///   - now: источник текущего момента.
    ///   - timeZone: часовой пояс устройства.
    ///   - save: операция сохранения контекста.
    init(
        container: ModelContainer, // Контейнер БД.
        now: @escaping @Sendable () -> Date = LedgerStore.systemNow, // Часы устройства по умолчанию.
        timeZone: @escaping @Sendable () -> TimeZone = LedgerStore.currentTimeZone, // Текущий пояс по умолчанию.
        save: @escaping SaveOperation = LedgerStore.contextSave // Обычное сохранение по умолчанию.
    ) {
        // Собственный контекст актора; запись только явная.
        let context = ModelContext(container)
        context.autosaveEnabled = false // Автосохранение не запишет неудачную операцию позже.
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context) // Актор выполняет всё на этом контексте.
        self.modelContainer = container // Контейнер для ModelActor.
        self.now = now // Источник времени.
        self.timeZone = timeZone // Источник часового пояса.
        self.save = save // Операция сохранения.
    }

    /// Текущий момент по системным часам.
    nonisolated private static func systemNow() -> Date { .now } // Часы устройства.
    /// Текущий часовой пояс устройства.
    nonisolated private static func currentTimeZone() -> TimeZone { .current } // Пояс читается при каждой операции.
    /// Обычное сохранение контекста.
    nonisolated private static func contextSave(_ context: ModelContext) throws { try context.save() } // ModelContext.save().

    // MARK: - LedgerSummaryProviding

    /// Создаёт недостающие системные категории и считает активные категории и расходы.
    func prepare() throws -> LedgerSummary {
        try ensureSystemCategories() // Повторяемая инициализация.
        // Активные категории.
        let categories = try modelContext.fetchCount(FetchDescriptor<Category>(predicate: #Predicate { !$0.isArchived }))
        // Неудалённые расходы.
        let expenses = try modelContext.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.deletedAt == nil }))
        return LedgerSummary(activeCategoryCount: categories, expenseCount: expenses) // Сводка.
    }

    // MARK: - CategoryRepository

    /// Категории в порядке `sortOrder`, затем момента создания и UUID.
    func categories(includeArchived: Bool) throws -> [CategorySnapshot] {
        try ensureSystemCategories() // Системные категории всегда доступны.
        // Запрос категорий с учётом архивных.
        let descriptor = includeArchived
            ? FetchDescriptor<Category>() // Все категории.
            : FetchDescriptor<Category>(predicate: #Predicate { !$0.isArchived }) // Только активные.
        return try modelContext.fetch(descriptor) // Читаем категории.
            .sorted { ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString) } // Стабильный порядок.
            .compactMap(snapshot(of:)) // Неизвестные системные категории (из будущего реестра) не показываются.
    }

    /// Категория по UUID.
    func category(id: UUID) throws -> CategorySnapshot? {
        try ensureSystemCategories() // Системные категории всегда доступны.
        return try fetchCategory(id: id).flatMap(snapshot(of:)) // Снимок или nil.
    }

    /// Создаёт пользовательскую категорию; одинаковые названия допустимы (в контракте уникальности нет).
    func createCategory(_ new: NewCategory) throws -> CategorySnapshot {
        // Проверенные поля.
        let name = try CategoryRules.validatedName(new.name)
        let emoji = try CategoryRules.validatedEmoji(new.emoji) // Одна графема.
        let colorIndex = try CategoryRules.validatedColorIndex(new.colorIndex) // Индекс палитры.
        try ensureSystemCategories() // Порядок новой категории — после системных.
        return try write { // Одна транзакция: категория и мутация.
            // Порядок: после всех существующих категорий.
            let sortOrder = (try maxCategorySortOrder() ?? 0) + 1
            // Новая категория.
            let category = Category(
                id: UUID(), kind: .user, name: name, emoji: emoji, colorIndex: colorIndex, // Новый UUID клиента, поля пользователя.
                sortOrder: sortOrder, now: now() // Порядок и момент создания.
            )
            modelContext.insert(category) // Новая запись в контексте.
            try enqueue(category) // Мутация в той же транзакции.
            return snapshot(of: category)! // У пользовательской категории снимок есть всегда.
        }
    }

    /// Меняет поля неархивной пользовательской категории.
    func updateCategory(id: UUID, _ changes: NewCategory) throws -> CategorySnapshot {
        // Проверенные поля.
        let name = try CategoryRules.validatedName(changes.name)
        let emoji = try CategoryRules.validatedEmoji(changes.emoji) // Одна графема.
        let colorIndex = try CategoryRules.validatedColorIndex(changes.colorIndex) // Индекс палитры.
        try ensureSystemCategories() // Системная категория должна распознаваться как системная.
        return try write { // Одна транзакция: правка и мутация.
            guard let category = try fetchCategory(id: id) else { throw LedgerError.categoryNotFound } // Категория есть.
            guard category.kindRaw == CategoryKind.user.rawValue else { throw LedgerError.systemCategoryNotEditable } // Только пользовательская.
            guard !category.isArchived else { throw LedgerError.categoryArchived } // Архивная не правится.
            category.name = name // Название.
            category.emoji = emoji // Эмодзи.
            category.colorIndex = colorIndex // Цвет.
            category.updatedAt = now() // Момент изменения.
            try enqueue(category) // Мутация в той же транзакции.
            return snapshot(of: category)! // Снимок пользовательской категории.
        }
    }

    /// Архивирует категорию. Повторное архивирование ничего не меняет.
    func archiveCategory(id: UUID) throws -> CategorySnapshot {
        try ensureSystemCategories() // Системная категория должна существовать локально.
        return try write { // Одна транзакция: архивирование и мутация.
            guard let category = try fetchCategory(id: id), let current = snapshot(of: category) else { // Категория и её снимок.
                throw LedgerError.categoryNotFound // Категории нет.
            }
            guard current.isArchivable else { throw LedgerError.categoryNotArchivable } // «Другое».
            guard !category.isArchived else { return current } // Уже архивная: без новой мутации.
            category.isArchived = true // Архивирование; связи расходов не меняются.
            category.updatedAt = now() // Момент изменения.
            try enqueue(category) // Мутация в той же транзакции.
            return snapshot(of: category)! // Снимок после изменения.
        }
    }

    // MARK: - ExpenseRepository

    /// Создаёт расход и снимает отметку «День без расходов» на эту дату.
    func createExpense(_ draft: ExpenseDraft) throws -> ExpenseSnapshot {
        // Проверенные поля.
        let amount = try ExpenseAmountRule.validated(draft.amount)
        let comment = try ExpenseCommentRule.validated(draft.comment) // Нормализованный комментарий ≤ 200.
        try ensureSystemCategories() // Системные категории доступны для выбора.
        return try write { // Одна транзакция: расход, мутация, отметка дня.
            try requireAvailableCategory(id: draft.categoryID) // Новые расходы — только в неархивные категории.
            // Новый расход.
            let expense = Expense(
                id: UUID(), amountMinorUnits: amount.minorUnits, categoryID: draft.categoryID, // Новый UUID клиента, сумма и категория.
                dateKey: draft.date.storageKey, comment: comment, now: now() // День, комментарий, момент создания.
            )
            modelContext.insert(expense) // Новая запись в контексте.
            try enqueue(expense) // Мутация расхода.
            try clearDayMark(on: draft.date) // Расход главнее отметки (план §4).
            return snapshot(of: expense) // Снимок нового расхода.
        }
    }

    /// Неудалённый расход по UUID.
    func expense(id: UUID) throws -> ExpenseSnapshot? {
        try fetchLiveExpense(id: id).map(snapshot(of:)) // Удалённые не возвращаются.
    }

    /// Неудалённые расходы за период, при необходимости — одной категории.
    func expenses(in period: ClosedRange<CalendarDate>, categoryID: UUID?) throws -> [ExpenseSnapshot] {
        // Границы периода как ключи хранения.
        let lower = period.lowerBound.storageKey
        let upper = period.upperBound.storageKey // Верхняя граница включительно.
        // Запрос с фильтром по категории или без него.
        let descriptor: FetchDescriptor<Expense>
        if let categoryID { // Фильтр по категории задан.
            descriptor = FetchDescriptor(predicate: #Predicate { // Живые расходы периода одной категории.
                $0.deletedAt == nil && $0.dateKey >= lower && $0.dateKey <= upper && $0.categoryID == categoryID // Без удалённых, границы включительно.
            })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { // Живые расходы периода.
                $0.deletedAt == nil && $0.dateKey >= lower && $0.dateKey <= upper // Без удалённых, границы включительно.
            })
        }
        return try modelContext.fetch(descriptor) // Читаем расходы.
            .sorted(by: Self.historyOrder) // Стабильный порядок истории.
            .map(snapshot(of:)) // Снимки.
    }

    /// Меняет поля расхода. Перенос в архивную категорию запрещён; расход, уже лежащий в архивной, правится.
    func updateExpense(id: UUID, _ draft: ExpenseDraft) throws -> ExpenseSnapshot {
        // Проверенные поля.
        let amount = try ExpenseAmountRule.validated(draft.amount)
        let comment = try ExpenseCommentRule.validated(draft.comment) // Нормализованный комментарий ≤ 200.
        try ensureSystemCategories() // Системные категории доступны для выбора.
        return try write { // Одна транзакция: правка, мутация, отметка дня.
            guard let expense = try fetchLiveExpense(id: id) else { throw LedgerError.notFound } // Живой расход.
            if expense.categoryID != draft.categoryID { // Категория меняется.
                try requireAvailableCategory(id: draft.categoryID) // Перенос — только в неархивную категорию.
            }
            expense.amountMinorUnits = amount.minorUnits // Сумма.
            expense.categoryID = draft.categoryID // Категория.
            expense.dateKey = draft.date.storageKey // День.
            expense.comment = comment // Комментарий.
            expense.updatedAt = now() // Момент изменения.
            try enqueue(expense) // Мутация расхода.
            try clearDayMark(on: draft.date) // На новой дате отметка тоже снимается.
            return snapshot(of: expense) // Снимок после изменения.
        }
    }

    /// Удаляет расход: ставит `deletedAt` и регистрирует мутацию удаления. Запись хранится для sync.
    func deleteExpense(id: UUID) throws {
        try write { // Одна транзакция: tombstone и мутация.
            guard let expense = try fetchLiveExpense(id: id) else { throw LedgerError.notFound } // Живой расход.
            // Момент удаления.
            let deletedAt = now()
            expense.deletedAt = deletedAt // Tombstone.
            expense.updatedAt = deletedAt // Момент изменения совпадает с удалением.
            try enqueue(expense) // Мутация удаления в той же транзакции.
        }
    }

    // MARK: - DayMarkRepository

    /// Отметка дня.
    func dayMark(on date: CalendarDate) throws -> DayMarkSnapshot? {
        try fetchDayMark(on: date).map(snapshot(of:)) // Снимок или nil.
    }

    /// Ставит или снимает отметку дня. Поставить отметку на день с расходами или в будущем нельзя.
    func setDayMarked(_ isMarked: Bool, on date: CalendarDate) throws -> DayMarkSnapshot {
        guard date <= CalendarDate.today(in: timeZone(), now: now()) else { throw LedgerError.dateInFuture } // Сервер отклоняет даты в будущем.
        return try write { // Одна транзакция: отметка и мутация.
            if isMarked { // Ставим отметку.
                guard try liveExpenseCount(on: date) == 0 else { throw LedgerError.dayHasExpenses } // Расход главнее отметки.
            }
            // Существующая или новая отметка.
            let mark: DayMark
            if let existing = try fetchDayMark(on: date) { // Отметка уже есть.
                guard existing.isMarked != isMarked else { return snapshot(of: existing) } // Без изменений — без мутации.
                existing.isMarked = isMarked // Новое состояние.
                existing.updatedAt = now() // Момент изменения.
                mark = existing // Меняем существующую.
            } else {
                mark = DayMark(id: DayMarkID.make(for: date), dateKey: date.storageKey, isMarked: isMarked, now: now()) // Первая отметка этой даты (UUIDv5).
                modelContext.insert(mark) // Новая запись в контексте.
            }
            try enqueue(mark) // Мутация отметки в той же транзакции.
            return snapshot(of: mark) // Снимок отметки.
        }
    }

    // MARK: - Outbox

    /// Неотправленные мутации в порядке отправки (для SyncEngine следующего этапа и тестов).
    func pendingMutations() throws -> [OutboxMutationSnapshot] {
        // Все мутации по порядку.
        let descriptor = FetchDescriptor<OutboxMutation>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { mutation in // Мутации как Sendable-снимки.
            OutboxMutationSnapshot( // Снимок мутации.
                mutationID: mutation.mutationID, // Ключ идемпотентности.
                sequence: mutation.sequence, // Порядок.
                entityType: SyncEntityType(rawValue: mutation.entityTypeRaw)!, // Пишется только из SyncEntityType.
                entityID: mutation.entityID, // UUID записи.
                operation: SyncOperation(rawValue: mutation.opRaw)!, // Пишется только из SyncOperation.
                baseVersion: mutation.baseVersion, // Базовая версия.
                entityCreatedAt: mutation.entityCreatedAt, // createdAt.
                updatedAt: mutation.updatedAt, // updatedAt.
                deletedAt: mutation.deletedAt, // deletedAt.
                schemaVersion: mutation.schemaVersion, // Версия формата.
                payload: mutation.payload // Тело.
            )
        }
    }

    // MARK: - Транзакции

    /// Выполняет изменения и сохраняет их одним `save()`. При любой ошибке откатывает контекст
    /// и пробрасывает исходную ошибку. Тело синхронное: внутри транзакции нет `await`.
    private func write<Value>(_ body: () throws -> Value) throws -> Value {
        do { // Транзакция.
            // Результат операции до сохранения.
            let result = try body()
            try save(modelContext) // Явная запись.
            return result // Результат после успешного сохранения.
        } catch { // Любая ошибка: проверки или сохранения.
            modelContext.rollback() // Ни одна часть операции не остаётся в контексте.
            throw error // Исходная ошибка вызывающему коду.
        }
    }

    /// Создаёт недостающие системные категории из реестра. Существующие не меняются:
    /// архивирование не сбрасывается, дубликаты не создаются.
    private func ensureSystemCategories() throws {
        guard !systemCategoriesReady else { return } // Уже проверено в этом хранилище.
        try write { // Одна транзакция на весь набор.
            // UUID системных категорий из реестра.
            let registryIDs = SystemCategory.allCases.map(\.id)
            // UUID системных категорий, которые уже есть локально.
            let existing = Set(try modelContext.fetch(FetchDescriptor<Category>(predicate: #Predicate {
                registryIDs.contains($0.id) // Только UUID из реестра.
            })).map(\.id)) // UUID найденных записей.
            for system in SystemCategory.allCases where !existing.contains(system.id) { // Только отсутствующие.
                modelContext.insert(Category( // Строка системной категории.
                    id: system.id, kind: .system, name: nil, emoji: nil, colorIndex: nil, // UUID реестра; определение не хранится.
                    sortOrder: system.sortOrder, now: now() // Порядок из реестра.
                )) // Определение — константа приложения; мутация не нужна, пока состояние не менялось.
            }
        }
        systemCategoriesReady = true // Следующие операции не проверяют повторно.
    }

    /// Добавляет мутацию upsert категории в outbox.
    private func enqueue(_ category: Category) throws {
        // Payload по виду категории.
        let payload = category.kindRaw == CategoryKind.system.rawValue
            ? CategoryPayloadDTO(kind: CategoryKind.system.rawValue, name: nil, emoji: nil, colorIndex: nil, sortOrder: nil, isArchived: category.isArchived) // Системная: только состояние.
            : CategoryPayloadDTO( // Пользовательская: все поля.
                kind: CategoryKind.user.rawValue, name: category.name, emoji: category.emoji, // Вид, название, эмодзи.
                colorIndex: category.colorIndex, sortOrder: category.sortOrder, isArchived: category.isArchived // Цвет, порядок, архивирование.
            )
        try enqueueMutation( // Мутация категории.
            entityType: .category, entityID: category.id, operation: .upsert, baseVersion: category.serverVersion, // Тип, UUID, upsert, базовая версия.
            createdAt: category.createdAt, updatedAt: category.updatedAt, deletedAt: nil, // Моменты записи.
            payload: try SyncPayloadCoder.encode(payload) // JSON payload.
        ) // Категории не удаляются, только upsert.
    }

    /// Добавляет мутацию расхода в outbox: upsert для живого, delete для tombstone.
    private func enqueue(_ expense: Expense) throws {
        if let deletedAt = expense.deletedAt { // Расход удалён.
            try enqueueMutation( // Мутация удаления.
                entityType: .expense, entityID: expense.id, operation: .delete, baseVersion: expense.serverVersion, // Тип, UUID, delete, базовая версия.
                createdAt: expense.createdAt, updatedAt: expense.updatedAt, deletedAt: deletedAt, payload: nil // Моменты и deletedAt, без payload.
            ) // Tombstone: payload пустой.
            return // Upsert не нужен.
        }
        // Payload расхода.
        let payload = ExpensePayloadDTO(
            amount: Money(minorUnits: expense.amountMinorUnits).apiString, // Decimal-строка.
            categoryId: expense.categoryID.contractString, // UUID в нижнем регистре.
            date: try CalendarDate(storageKey: expense.dateKey).isoString, // YYYY-MM-DD.
            comment: expense.comment // Нормализованный комментарий.
        )
        try enqueueMutation( // Мутация расхода.
            entityType: .expense, entityID: expense.id, operation: .upsert, baseVersion: expense.serverVersion, // Тип, UUID, upsert, базовая версия.
            createdAt: expense.createdAt, updatedAt: expense.updatedAt, deletedAt: nil, // Моменты записи.
            payload: try SyncPayloadCoder.encode(payload) // JSON payload.
        )
    }

    /// Добавляет мутацию upsert отметки дня в outbox.
    private func enqueue(_ mark: DayMark) throws {
        // Payload отметки.
        let payload = DayMarkPayloadDTO(date: try CalendarDate(storageKey: mark.dateKey).isoString, isMarked: mark.isMarked)
        try enqueueMutation( // Мутация отметки.
            entityType: .dayMark, entityID: mark.id, operation: .upsert, baseVersion: mark.serverVersion, // Тип, UUID, upsert, базовая версия.
            createdAt: mark.createdAt, updatedAt: mark.updatedAt, deletedAt: nil, // Моменты записи.
            payload: try SyncPayloadCoder.encode(payload) // JSON payload.
        ) // Отметки не удаляются, только upsert.
    }

    /// Вставляет мутацию со следующим порядковым номером.
    private func enqueueMutation(
        entityType: SyncEntityType, // Тип сущности.
        entityID: UUID, // UUID записи.
        operation: SyncOperation, // Операция.
        baseVersion: Int64, // Базовая версия.
        createdAt: Date, // createdAt записи.
        updatedAt: Date, // updatedAt записи.
        deletedAt: Date?, // deletedAt для удаления.
        payload: Data? // Тело.
    ) throws { // Ошибка кодирования или чтения откатит транзакцию.
        // Последняя мутация, включая ещё не сохранённые в этой транзакции.
        var last = FetchDescriptor<OutboxMutation>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        last.fetchLimit = 1 // Нужна одна запись.
        // Следующий номер.
        let sequence = (try modelContext.fetch(last).first?.sequence ?? 0) + 1
        modelContext.insert(OutboxMutation( // Новая мутация в той же транзакции.
            mutationID: UUID(), sequence: sequence, entityType: entityType, entityID: entityID, // Новый mutationId и порядковый номер.
            operation: operation, baseVersion: baseVersion, entityCreatedAt: createdAt, updatedAt: updatedAt, // Операция, база и моменты.
            deletedAt: deletedAt, schemaVersion: SyncSchema.version, payload: payload // deletedAt, версия формата, тело.
        ))
    }

    /// Снимает отметку «День без расходов», если она стоит на дате нового или перенесённого расхода.
    private func clearDayMark(on date: CalendarDate) throws {
        guard let mark = try fetchDayMark(on: date), mark.isMarked else { return } // Снимать нечего.
        mark.isMarked = false // Расход главнее отметки; после удаления расхода не восстанавливается.
        mark.updatedAt = now() // Момент изменения.
        try enqueue(mark) // Мутация в той же транзакции.
    }

    // MARK: - Чтение

    /// Категория по UUID.
    private func fetchCategory(id: UUID) throws -> Category? {
        // Запрос одной категории.
        var descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1 // Нужна одна запись.
        return try modelContext.fetch(descriptor).first // Категория или nil.
    }

    /// Проверяет, что категория существует и не архивирована.
    private func requireAvailableCategory(id: UUID) throws {
        guard let category = try fetchCategory(id: id) else { throw LedgerError.categoryNotFound } // Категория есть.
        guard !category.isArchived else { throw LedgerError.categoryArchived } // Архивная недоступна.
    }

    /// Наибольший `sortOrder` среди категорий.
    private func maxCategorySortOrder() throws -> Int? {
        // Категория с наибольшим порядком.
        var descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1 // Нужна одна запись.
        return try modelContext.fetch(descriptor).first?.sortOrder // Порядок или nil.
    }

    /// Неудалённый расход по UUID.
    private func fetchLiveExpense(id: UUID) throws -> Expense? {
        // Запрос одного живого расхода.
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        descriptor.fetchLimit = 1 // Нужна одна запись.
        return try modelContext.fetch(descriptor).first // Расход или nil.
    }

    /// Число неудалённых расходов на дату.
    private func liveExpenseCount(on date: CalendarDate) throws -> Int {
        // Ключ дня.
        let key = date.storageKey
        return try modelContext.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { // Число живых расходов на день.
            $0.deletedAt == nil && $0.dateKey == key // Без удалённых.
        })) // Число расходов.
    }

    /// Отметка дня по дате.
    private func fetchDayMark(on date: CalendarDate) throws -> DayMark? {
        // UUIDv5 отметки.
        let id = DayMarkID.make(for: date)
        // Запрос одной отметки.
        var descriptor = FetchDescriptor<DayMark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1 // Нужна одна запись.
        return try modelContext.fetch(descriptor).first // Отметка или nil.
    }

    // MARK: - Снимки

    /// Порядок истории: дата ↓, момент создания ↓, UUID ↑.
    nonisolated private static func historyOrder(_ lhs: Expense, _ rhs: Expense) -> Bool {
        if lhs.dateKey != rhs.dateKey { return lhs.dateKey > rhs.dateKey } // Новые дни выше.
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt } // В дне — новые выше.
        return lhs.id.uuidString < rhs.id.uuidString // Детерминированный разрыв ничьей.
    }

    /// Снимок категории; `nil` для системного UUID вне реестра приложения.
    private func snapshot(of category: Category) -> CategorySnapshot? {
        if category.kindRaw == CategoryKind.system.rawValue { // Системная категория.
            guard let system = SystemCategory(id: category.id) else { return nil } // Неизвестная системная категория.
            return CategorySnapshot( // Снимок системной категории.
                id: category.id, kind: .system, title: .system(system), emoji: system.emoji, // UUID, вид, название и эмодзи из реестра.
                colorIndex: system.colorIndex, sortOrder: system.sortOrder, // Цвет и порядок из реестра.
                isArchived: category.isArchived, isArchivable: system.isArchivable // Состояние из БД.
            ) // Определение — из реестра, состояние — из БД.
        }
        return CategorySnapshot( // Снимок пользовательской категории.
            id: category.id, kind: .user, title: .user(category.name ?? ""), emoji: category.emoji ?? "", // Поля из БД.
            colorIndex: category.colorIndex ?? 0, sortOrder: category.sortOrder, // Цвет и порядок.
            isArchived: category.isArchived, isArchivable: true // Состояние.
        ) // Пользовательская категория.
    }

    /// Снимок расхода.
    private func snapshot(of expense: Expense) -> ExpenseSnapshot {
        ExpenseSnapshot( // Снимок расхода.
            id: expense.id, // UUID.
            amount: Money(minorUnits: expense.amountMinorUnits), // Сумма.
            categoryID: expense.categoryID, // Категория.
            date: try! CalendarDate(storageKey: expense.dateKey), // Ключ пишется только из CalendarDate.
            comment: expense.comment, // Комментарий.
            createdAt: expense.createdAt, // Момент создания.
            updatedAt: expense.updatedAt // Момент изменения.
        )
    }

    /// Снимок отметки дня.
    private func snapshot(of mark: DayMark) -> DayMarkSnapshot {
        DayMarkSnapshot(date: try! CalendarDate(storageKey: mark.dateKey), isMarked: mark.isMarked) // Ключ пишется только из CalendarDate.
    }
}
