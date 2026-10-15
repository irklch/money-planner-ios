// LedgerStoreTests.swift
// Тесты хранилища расходов, категорий и отметок дня: правила данных, outbox, tombstones,
// атомарность и откат при ошибке сохранения.

// Foundation нужен для Date, UUID, URL и TimeZone.
import Foundation
// SwiftData нужен для ModelContainer, ModelContext и FetchDescriptor.
import SwiftData
// Testing нужен для @Suite, @Test, #expect и #require.
import Testing
// Доступ к внутренним типам приложения.
@testable import MoneyPlanner

/// Тесты `LedgerStore`. MainActor: инициализатор хранилища выполняется на MainActor.
@MainActor
@Suite("LedgerStore") // Набор тестов.
struct LedgerStoreTests { // Тесты LedgerStore.
    /// Начальный момент часов в тестах (2026-10-14 09:00 UTC).
    private static let start = Date(timeIntervalSince1970: 1_791_968_400)
    /// «Сегодня» для часов тестов в UTC.
    private static let today = CalendarDate.iso("2026-10-14")

    /// Хранилище с управляемыми часами и сохранением поверх изолированной БД.
    @MainActor
    private struct Fixture { // Окружение одного теста.
        /// Контейнер БД теста.
        let container: ModelContainer
        /// Управляемые часы.
        let clock: StoreTestClock
        /// Управляемое сохранение.
        let saver: ControlledStoreSave
        /// Проверяемое хранилище.
        let store: LedgerStore

        /// Создаёт хранилище поверх переданного контейнера или новой БД в памяти.
        init(container: ModelContainer? = nil, timeZone: TimeZone = .gmt) throws {
            self.container = try container ?? ModelContainerFactory.makeInMemory() // Изолированная БД по умолчанию.
            // Часы с начальным моментом теста.
            let clock = StoreTestClock(LedgerStoreTests.start)
            // Сохранение, которое можно заставить упасть.
            let saver = ControlledStoreSave()
            self.clock = clock // Часы доступны тесту.
            self.saver = saver // Сохранение доступно тесту.
            store = LedgerStore( // Хранилище с точками подмены.
                container: self.container, // Общий контейнер теста.
                now: { clock.now }, // Время из управляемых часов.
                timeZone: { timeZone }, // Заданный часовой пояс.
                save: { try saver.save($0) } // Управляемое сохранение.
            )
        }

        /// Независимый контекст: видит только сохранённое в хранилище.
        func independentContext() -> ModelContext {
            ModelContext(container) // Новый контекст того же контейнера.
        }

        /// Черновик расхода с удобными значениями по умолчанию.
        func draft(_ amount: String = "100.00", category: SystemCategory = .products, date: String = "2026-10-14", comment: String? = nil) -> ExpenseDraft {
            ExpenseDraft(amount: .api(amount), categoryID: category.id, date: .iso(date), comment: comment) // Черновик из строк.
        }
    }

    // MARK: - Системные категории

    /// Первая подготовка создаёт 12 системных категорий без мутаций outbox.
    @Test func prepareSeedsSystemCategoriesWithoutMutations() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Сводка после первой подготовки.
        let summary = try await fixture.store.prepare()
        #expect(summary.activeCategoryCount == 12) // Все системные категории активны.
        // Все категории, включая архивные.
        let categories = try await fixture.store.categories(includeArchived: true)
        #expect(categories.map(\.id) == SystemCategory.allCases.map(\.id)) // Порядок реестра, «Другое» последней.
        #expect(categories.allSatisfy { $0.kind == .system && !$0.isArchived }) // Только системные и активные.
        #expect(categories.last?.title == .system(.other)) // «Другое» в конце (sortOrder 99).
        #expect(try await fixture.store.pendingMutations().isEmpty) // Инициализация не попадает в outbox.
    }

    /// Повторная инициализация (новый экземпляр, повторное открытие) не создаёт дубликатов
    /// и не сбрасывает архивирование.
    @Test func reseedingKeepsArchiveAndCreatesNoDuplicates() async throws {
        // Первое хранилище: инициализация и архивирование.
        let first = try Fixture()
        _ = try await first.store.prepare() // Создаём системные категории.
        _ = try await first.store.archiveCategory(id: SystemCategory.travel.id) // Архивируем «Путешествия».

        // Второе хранилище поверх той же БД (как после перезапуска).
        let second = try Fixture(container: first.container)
        _ = try await second.store.prepare() // Повторная инициализация.
        _ = try await second.store.prepare() // И ещё одна — без эффекта.

        // Независимый контекст для проверки содержимого БД.
        let context = second.independentContext()
        #expect(try context.fetchCount(FetchDescriptor<MoneyPlanner.Category>()) == 12) // Дубликатов нет.
        #expect(try await second.store.category(id: SystemCategory.travel.id)?.isArchived == true) // Архивирование сохранено.
        #expect(try await second.store.prepare().activeCategoryCount == 11) // Активных на одну меньше.
    }

    /// Параллельные вызовы одного хранилища не создают дубликатов системных категорий.
    @Test func concurrentPreparationCreatesNoDuplicates() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Хранилище для дочерних задач.
        let store = fixture.store
        try await withThrowingTaskGroup(of: Void.self) { group in // 20 одновременных обращений.
            for index in 0..<20 { // Чередуем подготовку и чтение списка.
                group.addTask { // Отдельная задача.
                    if index.isMultiple(of: 2) { // Чётные — подготовка.
                        _ = try await store.prepare() // Инициализация категорий.
                    } else { // Нечётные — чтение.
                        _ = try await store.categories(includeArchived: false) // Чтение тоже инициализирует.
                    }
                }
            }
            try await group.waitForAll() // Ждём все задачи.
        }
        #expect(try fixture.independentContext().fetchCount(FetchDescriptor<MoneyPlanner.Category>()) == 12) // Ровно 12 записей.
    }

    /// «Другое» не архивируется; остальные системные архивируются и регистрируют состояние в outbox.
    @Test func archivesSystemCategoryExceptFallback() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        await #expect(throws: LedgerError.categoryNotArchivable) { // «Другое» архивировать нельзя.
            try await fixture.store.archiveCategory(id: SystemCategory.other.id) // Операция, которая должна выбросить ошибку.
        }
        // Архивированная системная категория.
        let archived = try await fixture.store.archiveCategory(id: SystemCategory.gifts.id)
        #expect(archived.isArchived) // Состояние изменилось.
        _ = try await fixture.store.archiveCategory(id: SystemCategory.gifts.id) // Повтор — без новой мутации.

        // Мутации outbox.
        let mutations = try await fixture.store.pendingMutations()
        #expect(mutations.count == 1) // Только одно архивирование.
        // Единственная мутация.
        let mutation = try #require(mutations.first)
        #expect(mutation.entityType == .category) // Тип сущности.
        #expect(mutation.entityID == SystemCategory.gifts.id) // UUID из реестра.
        #expect(mutation.operation == .upsert) // Категории только upsert.
        #expect(mutation.baseVersion == 0) // Запись на сервере ещё не создана.
        // Payload мутации.
        let payload = try SyncPayloadCoder.decode(CategoryPayloadDTO.self, from: try #require(mutation.payload))
        #expect(payload == CategoryPayloadDTO(kind: "system", name: nil, emoji: nil, colorIndex: nil, sortOrder: nil, isArchived: true)) // Только состояние.
        #expect(String(decoding: try #require(mutation.payload), as: UTF8.self) == #"{"isArchived":true,"kind":"system"}"#) // Точное тело JSON.
        await #expect(throws: LedgerError.systemCategoryNotEditable) { // Системную категорию не переименовать.
            try await fixture.store.updateCategory(id: SystemCategory.products.id, NewCategory(name: "Еда", emoji: "🍞", colorIndex: 0)) // Операция, которая должна выбросить ошибку.
        }
    }

    // MARK: - Пользовательские категории

    /// Пользовательская категория сохраняет поля и регистрирует мутацию `kind: user`.
    @Test func createsUserCategory() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Новая категория с пробелами вокруг названия.
        let created = try await fixture.store.createCategory(NewCategory(name: "  Кофе ", emoji: "☕️", colorIndex: 5))
        #expect(created.kind == .user) // Пользовательская.
        #expect(created.title == .user("Кофе")) // Название без пробелов по краям.
        #expect(created.emoji == "☕️") // Эмодзи.
        #expect(created.colorIndex == 5) // Цвет палитры.
        #expect(created.sortOrder == 100) // После «Другое» (99).
        #expect(!created.isArchived) // Активна.
        #expect(created.isArchivable) // Архивируется.
        #expect(try await fixture.store.categories(includeArchived: false).last == created) // Последняя в списке.

        // Вторая категория с тем же названием: в контракте уникальности нет.
        let duplicate = try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5))
        #expect(duplicate.id != created.id) // Отдельная запись.
        #expect(duplicate.sortOrder == 101) // Следующая по порядку.

        // Первая мутация outbox.
        let mutation = try #require(try await fixture.store.pendingMutations().first)
        #expect(mutation.entityID == created.id) // Мутация первой категории.
        // Payload мутации.
        let payload = try SyncPayloadCoder.decode(CategoryPayloadDTO.self, from: try #require(mutation.payload))
        #expect(payload == CategoryPayloadDTO(kind: "user", name: "Кофе", emoji: "☕️", colorIndex: 5, sortOrder: 100, isArchived: false)) // Полный UserCategoryPayload.
    }

    /// Некорректные поля отклоняются до записи.
    @Test func rejectsInvalidUserCategory() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        await #expect(throws: LedgerError.invalidCategoryName) { // 25 символов — больше лимита.
            try await fixture.store.createCategory(NewCategory(name: String(repeating: "а", count: 25), emoji: "☕️", colorIndex: 0)) // Операция, которая должна выбросить ошибку.
        }
        await #expect(throws: LedgerError.invalidEmoji) { // Две графемы.
            try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️🍰", colorIndex: 0)) // Операция, которая должна выбросить ошибку.
        }
        await #expect(throws: LedgerError.invalidColorIndex) { // Индекс вне палитры.
            try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 12)) // Операция, которая должна выбросить ошибку.
        }
        #expect(try await fixture.store.categories(includeArchived: true).count == 12) // Лишних категорий нет.
        #expect(try await fixture.store.pendingMutations().isEmpty) // Мутаций нет.
    }

    /// Правка меняет поля неархивной пользовательской категории; архивную править нельзя.
    @Test func updatesUserCategory() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Исходная категория.
        let created = try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5))
        fixture.clock.advance(by: 60) // Правка через минуту.
        // Категория после правки.
        let updated = try await fixture.store.updateCategory(id: created.id, NewCategory(name: "Чай", emoji: "🍵", colorIndex: 2))
        #expect(updated.title == .user("Чай")) // Новое название.
        #expect(updated.emoji == "🍵") // Новый эмодзи.
        #expect(updated.colorIndex == 2) // Новый цвет.
        #expect(updated.sortOrder == created.sortOrder) // Порядок не меняется.

        _ = try await fixture.store.archiveCategory(id: created.id) // Архивируем.
        await #expect(throws: LedgerError.categoryArchived) { // Архивную править нельзя.
            try await fixture.store.updateCategory(id: created.id, NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5)) // Операция, которая должна выбросить ошибку.
        }
        // Операции в outbox.
        let operations = try await fixture.store.pendingMutations().map(\.operation)
        #expect(operations == [.upsert, .upsert, .upsert]) // Создание, правка, архивирование.
    }

    // MARK: - Архивная категория

    /// Архивная категория остаётся в истории, но недоступна для новых расходов и переноса.
    @Test func archivedCategoryStaysInHistory() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Пользовательская категория.
        let user = try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5))
        // Расход в пользовательской категории.
        let inUser = try await fixture.store.createExpense(ExpenseDraft(amount: .api("150.00"), categoryID: user.id, date: Self.today, comment: nil))
        // Расход в системной категории «Кафе».
        let inSystem = try await fixture.store.createExpense(fixture.draft(category: .cafe))
        // Расход в активной категории «Продукты».
        let other = try await fixture.store.createExpense(fixture.draft(category: .products))

        _ = try await fixture.store.archiveCategory(id: user.id) // Архивируем пользовательскую.
        _ = try await fixture.store.archiveCategory(id: SystemCategory.cafe.id) // Архивируем системную.

        #expect(try await fixture.store.expense(id: inUser.id)?.categoryID == user.id) // Связь расхода сохранена.
        #expect(try await fixture.store.expenses(in: Self.today...Self.today, categoryID: SystemCategory.cafe.id).map(\.id) == [inSystem.id]) // История по архивной категории.
        #expect(try await fixture.store.category(id: user.id)?.isArchived == true) // Категория доступна по UUID.
        #expect(try await fixture.store.categories(includeArchived: true).contains { $0.id == user.id }) // Есть в полном списке.
        #expect(try await !fixture.store.categories(includeArchived: false).contains { $0.id == user.id }) // Нет в списке выбора.

        await #expect(throws: LedgerError.categoryArchived) { // Новый расход в архивную пользовательскую.
            try await fixture.store.createExpense(ExpenseDraft(amount: .api("1.00"), categoryID: user.id, date: Self.today, comment: nil)) // Операция, которая должна выбросить ошибку.
        }
        await #expect(throws: LedgerError.categoryArchived) { // Новый расход в архивную системную.
            try await fixture.store.createExpense(fixture.draft(category: .cafe)) // Операция, которая должна выбросить ошибку.
        }
        await #expect(throws: LedgerError.categoryArchived) { // Перенос расхода в архивную категорию.
            try await fixture.store.updateExpense(id: other.id, fixture.draft(category: .cafe)) // Операция, которая должна выбросить ошибку.
        }
        // Расход, уже лежащий в архивной категории, можно править.
        let edited = try await fixture.store.updateExpense(id: inSystem.id, fixture.draft("99.99", category: .cafe))
        #expect(edited.amount == .api("99.99")) // Сумма изменилась.
        #expect(edited.categoryID == SystemCategory.cafe.id) // Категория прежняя.
    }

    /// Расход в несуществующую категорию не создаётся.
    @Test func rejectsUnknownCategory() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        await #expect(throws: LedgerError.categoryNotFound) { // Случайный UUID категории.
            try await fixture.store.createExpense(ExpenseDraft(amount: .api("1.00"), categoryID: UUID(), date: Self.today, comment: nil)) // Операция, которая должна выбросить ошибку.
        }
    }

    // MARK: - Расходы

    /// Создание, чтение, изменение и удаление расхода с регистрацией мутаций.
    @Test func manualExpenseCRUD() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Новый расход с комментарием, который нужно нормализовать.
        let created = try await fixture.store.createExpense(fixture.draft("250.50", category: .cafe, date: "2026-10-13", comment: "  Обед\n"))
        #expect(created.amount == .api("250.50")) // Сумма.
        #expect(created.categoryID == SystemCategory.cafe.id) // Категория.
        #expect(created.date == .iso("2026-10-13")) // День.
        #expect(created.comment == "Обед") // Нормализованный комментарий.
        #expect(created.createdAt == Self.start) // Момент создания из часов.
        #expect(try await fixture.store.expense(id: created.id) == created) // Чтение по UUID.

        fixture.clock.advance(by: 120) // Правка через 2 минуты.
        // Расход после изменения всех полей.
        let updated = try await fixture.store.updateExpense(id: created.id, fixture.draft("300.00", category: .products, date: "2026-10-12", comment: nil))
        #expect(updated.amount == .api("300.00")) // Новая сумма.
        #expect(updated.categoryID == SystemCategory.products.id) // Новая категория.
        #expect(updated.date == .iso("2026-10-12")) // Новый день.
        #expect(updated.comment == nil) // Комментарий удалён.
        #expect(updated.createdAt == Self.start) // createdAt не меняется.
        #expect(updated.updatedAt == Self.start.addingTimeInterval(120)) // updatedAt обновлён.

        fixture.clock.advance(by: 60) // Удаление ещё через минуту.
        try await fixture.store.deleteExpense(id: created.id) // Удаляем.
        #expect(try await fixture.store.expense(id: created.id) == nil) // Удалённый не читается.
        await #expect(throws: LedgerError.notFound) { try await fixture.store.deleteExpense(id: created.id) } // Повторное удаление.
        await #expect(throws: LedgerError.notFound) { try await fixture.store.updateExpense(id: created.id, fixture.draft()) } // Правка удалённого.

        // Мутации outbox.
        let mutations = try await fixture.store.pendingMutations()
        #expect(mutations.map(\.operation) == [.upsert, .upsert, .delete]) // Создание, изменение, удаление.
        #expect(mutations.allSatisfy { $0.entityID == created.id && $0.entityType == .expense && $0.schemaVersion == 1 }) // Конверт мутаций.
        #expect(mutations.map(\.sequence) == [1, 2, 3]) // Порядок отправки.
        #expect(Set(mutations.map(\.mutationID)).count == 3) // Уникальные mutationId.

        // Payload создания.
        let firstPayload = try SyncPayloadCoder.decode(ExpensePayloadDTO.self, from: try #require(mutations[0].payload))
        #expect(firstPayload == ExpensePayloadDTO(amount: "250.50", categoryId: SystemCategory.cafe.idString, date: "2026-10-13", comment: "Обед")) // Поля ExpensePayload.
        // Точное тело JSON изменения.
        let secondJSON = String(decoding: try #require(mutations[1].payload), as: UTF8.self)
        #expect(secondJSON == #"{"amount":"300.00","categoryId":"00000000-0000-4000-8000-000000000001","date":"2026-10-12"}"#) // Без comment, UUID в нижнем регистре.
    }

    /// Некорректная сумма и длинный комментарий отклоняются до записи.
    @Test func rejectsInvalidExpenseFields() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        await #expect(throws: LedgerError.invalidAmount) { try await fixture.store.createExpense(fixture.draft("0.00")) } // Ноль.
        await #expect(throws: LedgerError.invalidAmount) { try await fixture.store.createExpense(fixture.draft("1000000000.00")) } // Больше максимума.
        await #expect(throws: LedgerError.commentTooLong) { // 201 кириллический символ.
            try await fixture.store.createExpense(fixture.draft(comment: String(repeating: "ж", count: 201))) // Операция, которая должна выбросить ошибку.
        }
        await #expect(throws: LedgerError.commentTooLong) { // 196 + 5 (👨‍👩‍👧) = 201 scalar values.
            try await fixture.store.createExpense(fixture.draft(comment: String(repeating: "a", count: 196) + "👨‍👩‍👧")) // Операция, которая должна выбросить ошибку.
        }
        // 198 + 2 (👍🏽) = 200 scalar values — граница допустима.
        let fits = try await fixture.store.createExpense(fixture.draft(comment: String(repeating: "ж", count: 198) + "👍🏽"))
        #expect(fits.comment?.unicodeScalars.count == 200) // Комментарий не обрезан.
        #expect(try await fixture.store.pendingMutations().count == 1) // Записался только допустимый расход.
    }

    /// Период включает обе границы; фильтр по категории; порядок стабилен при одинаковых датах.
    @Test func filtersPeriodAndCategoryWithStableOrder() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // День до начала периода.
        let beforeStart = try await fixture.store.createExpense(fixture.draft(date: "2026-09-30"))
        fixture.clock.advance(by: 1) // Следующий расход создаётся позже.
        // Первый день периода.
        let firstDay = try await fixture.store.createExpense(fixture.draft(date: "2026-10-01"))
        fixture.clock.advance(by: 1) // Позже.
        // Последний день периода, раньше по времени создания, «Кафе».
        let lastDayEarly = try await fixture.store.createExpense(fixture.draft(category: .cafe, date: "2026-10-31"))
        fixture.clock.advance(by: 1) // Позже.
        // Последний день периода, позже по времени создания.
        let lastDayLate = try await fixture.store.createExpense(fixture.draft(date: "2026-10-31"))
        fixture.clock.advance(by: 1) // Позже.
        // День после конца периода.
        let afterEnd = try await fixture.store.createExpense(fixture.draft(date: "2026-11-01"))
        // Два расхода с одинаковыми датой и моментом создания: порядок по UUID.
        let tieA = try await fixture.store.createExpense(fixture.draft(date: "2026-10-15"))
        // Второй расход той же ничьей.
        let tieB = try await fixture.store.createExpense(fixture.draft(date: "2026-10-15"))
        // Удалённый расход внутри периода.
        let deleted = try await fixture.store.createExpense(fixture.draft(date: "2026-10-15"))
        try await fixture.store.deleteExpense(id: deleted.id) // Tombstone не попадает в историю.

        // Октябрь целиком.
        let october = CalendarDate.iso("2026-10-01")...CalendarDate.iso("2026-10-31")
        // Все расходы октября.
        let all = try await fixture.store.expenses(in: october, categoryID: nil)
        // Ожидаемый порядок ничьей — UUID по возрастанию.
        let ties = [tieA.id, tieB.id].sorted { $0.uuidString < $1.uuidString }
        #expect(all.map(\.id) == [lastDayLate.id, lastDayEarly.id] + ties + [firstDay.id]) // Дата ↓, createdAt ↓, UUID ↑.
        #expect(!all.contains { [beforeStart.id, afterEnd.id, deleted.id].contains($0.id) }) // Вне периода и удалённые исключены.
        #expect(try await fixture.store.expenses(in: october, categoryID: nil) == all) // Повтор — тот же порядок.

        // Только «Кафе».
        let cafe = try await fixture.store.expenses(in: october, categoryID: SystemCategory.cafe.id)
        #expect(cafe.map(\.id) == [lastDayEarly.id]) // Фильтр по категории.
        // Период из одного дня.
        let singleDay = try await fixture.store.expenses(in: CalendarDate.iso("2026-10-31")...CalendarDate.iso("2026-10-31"), categoryID: nil)
        #expect(singleDay.map(\.id) == [lastDayLate.id, lastDayEarly.id]) // Граница включена.
    }

    /// Удалённый расход скрыт из истории, но tombstone и мутация удаления сохранены для sync.
    @Test func deletedExpenseKeepsSyncInformation() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Расход, который будет удалён.
        let expense = try await fixture.store.createExpense(fixture.draft("42.00"))
        fixture.clock.advance(by: 300) // Удаление через 5 минут.
        try await fixture.store.deleteExpense(id: expense.id) // Удаляем.

        #expect(try await fixture.store.expenses(in: Self.today...Self.today, categoryID: nil).isEmpty) // Нет в истории.
        #expect(try await fixture.store.prepare().expenseCount == 0) // Нет в сводке.

        // Независимый контекст.
        let context = fixture.independentContext()
        // UUID для предиката.
        let expenseID = expense.id
        // Запись в БД после удаления.
        let stored = try #require(try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == expenseID })).first)
        #expect(stored.deletedAt == Self.start.addingTimeInterval(300)) // Tombstone с моментом удаления.
        #expect(stored.createdAt == Self.start) // createdAt сохранён.

        // Последняя мутация — удаление.
        let delete = try #require(try await fixture.store.pendingMutations().last)
        #expect(delete.operation == .delete) // Операция удаления.
        #expect(delete.entityID == expense.id) // UUID расхода.
        #expect(delete.deletedAt == Self.start.addingTimeInterval(300)) // deletedAt.
        #expect(delete.entityCreatedAt == Self.start) // createdAt записи.
        #expect(delete.payload == nil) // Tombstone без payload.
        #expect(try context.fetchCount(FetchDescriptor<OutboxMutation>()) == 2) // Создание и удаление сохранены.
    }

    /// Дата расхода не зависит от часового пояса, в котором его читают.
    @Test func expenseDateDoesNotShiftWithTimeZone() async throws {
        // Общая БД двух «устройств».
        let container = try ModelContainerFactory.makeInMemory()
        // Хранилище в часовом поясе Москвы.
        let moscow = try Fixture(container: container, timeZone: try #require(TimeZone(identifier: "Europe/Moscow")))
        // Расход на 14 октября.
        let created = try await moscow.store.createExpense(moscow.draft(date: "2026-10-14"))

        // Хранилище в часовом поясе Лос-Анджелеса.
        let losAngeles = try Fixture(container: container, timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")))
        // Тот же расход, прочитанный в другом поясе.
        let read = try #require(try await losAngeles.store.expense(id: created.id))
        #expect(read.date == .iso("2026-10-14")) // День не сдвинулся.
        #expect(try await losAngeles.store.expenses(in: CalendarDate.iso("2026-10-14")...CalendarDate.iso("2026-10-14"), categoryID: nil).map(\.id) == [created.id]) // Фильтр по дню тот же.
    }

    /// Расходы и категории сохраняются после повторного открытия файловой БД.
    @Test func dataSurvivesReopeningStore() async throws {
        // Временный каталог теста.
        let directory = URL.temporaryDirectory.appending(path: "LedgerStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) } // Удаляем после теста.
        // Файл временной БД.
        let url = directory.appending(path: "Test.store")

        // UUID расхода из первого открытия.
        let expenseID: UUID
        // UUID категории из первого открытия.
        let categoryID: UUID
        do { // Первое открытие БД.
            // Хранилище первого открытия.
            let fixture = try Fixture(container: try ModelContainerFactory.makePersistent(at: url))
            categoryID = try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5)).id // Пользовательская категория.
            _ = try await fixture.store.archiveCategory(id: SystemCategory.travel.id) // Архивная системная.
            expenseID = try await fixture.store.createExpense(ExpenseDraft( // Расход с граничной суммой и эмодзи.
                amount: .api("999999999.99"), categoryID: categoryID, date: .iso("2024-02-29"), comment: "👨‍👩‍👧 Кофе" // Поля расхода.
            )).id // UUID созданной записи.
        }

        // Хранилище после повторного открытия.
        let fixture = try Fixture(container: try ModelContainerFactory.makePersistent(at: url))
        // Расход после повторного открытия.
        let expense = try #require(try await fixture.store.expense(id: expenseID))
        #expect(expense.amount == .api("999999999.99")) // Сумма без потерь.
        #expect(expense.date == .iso("2024-02-29")) // 29 февраля.
        #expect(expense.comment == "👨‍👩‍👧 Кофе") // Комментарий с ZWJ-эмодзи.
        #expect(try await fixture.store.category(id: categoryID)?.title == .user("Кофе")) // Пользовательская категория.
        #expect(try await fixture.store.category(id: SystemCategory.travel.id)?.isArchived == true) // Архивирование.
        #expect(try await fixture.store.categories(includeArchived: true).count == 13) // 12 системных + 1 своя.
        #expect(try await fixture.store.pendingMutations().count == 3) // Outbox сохранён.
    }

    // MARK: - Атомарность и откат

    /// Ошибка сохранения при создании: не остаётся ни расхода, ни мутации, ни снятой отметки.
    @Test func failedCreateLeavesNothing() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        _ = try await fixture.store.setDayMarked(true, on: Self.today) // Отметка, которую расход снял бы.
        // Outbox до неудачной операции.
        let mutationsBefore = try await fixture.store.pendingMutations()

        fixture.saver.failNext() // Следующее сохранение упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { try await fixture.store.createExpense(fixture.draft()) } // Исходная ошибка проброшена.

        #expect(try await fixture.store.expenses(in: Self.today...Self.today, categoryID: nil).isEmpty) // Расхода нет в контексте.
        #expect(try await fixture.store.pendingMutations() == mutationsBefore) // Outbox прежний.
        #expect(try await fixture.store.dayMark(on: Self.today)?.isMarked == true) // Отметка не снята.
        // Независимый контекст.
        let context = fixture.independentContext()
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0) // Расхода нет в БД.
        #expect(try context.fetchCount(FetchDescriptor<OutboxMutation>()) == mutationsBefore.count) // Мутаций не прибавилось.
    }

    /// Ошибка сохранения при изменении, удалении и архивировании: прежнее состояние, без новых мутаций.
    @Test func failedUpdateAndDeleteKeepPreviousState() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Сохранённый расход.
        let expense = try await fixture.store.createExpense(fixture.draft("10.00", comment: "Было"))
        // Outbox до неудачных операций.
        let mutationsBefore = try await fixture.store.pendingMutations()

        fixture.clock.advance(by: 60) // Правка позже.
        fixture.saver.failNext() // Сохранение правки упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { // Неудачная правка.
            try await fixture.store.updateExpense(id: expense.id, fixture.draft("20.00", category: .cafe, comment: "Стало")) // Операция, которая должна выбросить ошибку.
        }
        #expect(try await fixture.store.expense(id: expense.id) == expense) // Прежние значения и updatedAt.

        fixture.saver.failNext() // Сохранение удаления упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { try await fixture.store.deleteExpense(id: expense.id) } // Неудачное удаление.
        #expect(try await fixture.store.expense(id: expense.id) == expense) // Расход жив.
        #expect(try await fixture.store.pendingMutations() == mutationsBefore) // Outbox прежний.

        fixture.saver.failNext() // Сохранение архивирования упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { try await fixture.store.archiveCategory(id: SystemCategory.products.id) } // Неудачное архивирование.
        #expect(try await fixture.store.category(id: SystemCategory.products.id)?.isArchived == false) // Категория активна.
        #expect(try await fixture.store.pendingMutations() == mutationsBefore) // Outbox прежний.
        #expect(fixture.saver.failedSaves == 3) // Все три ошибки сработали.
    }

    /// Ошибка сохранения при первой инициализации категорий не оставляет частичного набора.
    @Test func failedSeedingLeavesNoCategories() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        fixture.saver.failNext() // Сохранение инициализации упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { try await fixture.store.prepare() } // Ошибка проброшена.
        #expect(try fixture.independentContext().fetchCount(FetchDescriptor<MoneyPlanner.Category>()) == 0) // В БД пусто.
        #expect(try await fixture.store.prepare().activeCategoryCount == 12) // Повтор успешен, без дубликатов.
    }

    /// После ошибки сохранения следующие операции работают корректно.
    @Test func operationsSucceedAfterFailure() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        fixture.saver.failNext() // Создание категории упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { // Неудачное создание.
            try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5)) // Операция, которая должна выбросить ошибку.
        }
        // Успешное создание после ошибки.
        let category = try await fixture.store.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5))
        #expect(category.sortOrder == 100) // Порядок не сдвинут неудачной попыткой.

        fixture.saver.failNext() // Создание расхода упадёт.
        await #expect(throws: SimulatedStoreSaveError.self) { // Неудачное создание расхода.
            try await fixture.store.createExpense(ExpenseDraft(amount: .api("1.00"), categoryID: category.id, date: Self.today, comment: nil)) // Операция, которая должна выбросить ошибку.
        }
        // Успешный расход после ошибки.
        let expense = try await fixture.store.createExpense(ExpenseDraft(amount: .api("2.00"), categoryID: category.id, date: Self.today, comment: nil))
        #expect(try await fixture.store.expenses(in: Self.today...Self.today, categoryID: nil) == [expense]) // Только успешный расход.

        // Мутации outbox.
        let mutations = try await fixture.store.pendingMutations()
        #expect(mutations.map(\.entityID) == [category.id, expense.id]) // Категория раньше расхода.
        #expect(mutations.map(\.sequence) == [1, 2]) // Номера без пропусков.
        // Независимый контекст.
        let context = fixture.independentContext()
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1) // Один расход в БД.
        #expect(try context.fetchCount(FetchDescriptor<MoneyPlanner.Category>()) == 13) // 12 системных + 1 своя.
    }

    // MARK: - День без расходов

    /// Отметка дня: UUIDv5, расход снимает отметку в той же транзакции, удаление её не восстанавливает.
    @Test func dayMarkInvariants() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Вчерашний день.
        let yesterday = CalendarDate.iso("2026-10-13")
        // Поставленная отметка.
        let mark = try await fixture.store.setDayMarked(true, on: yesterday)
        #expect(mark == DayMarkSnapshot(date: yesterday, isMarked: true)) // Отметка стоит.
        _ = try await fixture.store.setDayMarked(true, on: yesterday) // Повтор без изменения.
        #expect(try await fixture.store.pendingMutations().count == 1) // Без новой мутации.

        // Расход на отмеченный день.
        let expense = try await fixture.store.createExpense(fixture.draft(date: "2026-10-13"))
        #expect(try await fixture.store.dayMark(on: yesterday)?.isMarked == false) // Расход главнее отметки.

        try await fixture.store.deleteExpense(id: expense.id) // Удаляем последний расход дня.
        #expect(try await fixture.store.dayMark(on: yesterday)?.isMarked == false) // Отметка не восстанавливается.

        // Мутации отметки дня.
        let markMutations = try await fixture.store.pendingMutations().filter { $0.entityType == .dayMark }
        #expect(markMutations.count == 2) // Установка и снятие.
        #expect(markMutations.allSatisfy { $0.entityID == DayMarkID.make(for: yesterday) && $0.operation == .upsert }) // UUIDv5, только upsert.
        // Payload снятия.
        let cleared = try SyncPayloadCoder.decode(DayMarkPayloadDTO.self, from: try #require(markMutations.last?.payload))
        #expect(cleared == DayMarkPayloadDTO(date: "2026-10-13", isMarked: false)) // DayMarkPayload.
    }

    /// Нельзя отметить день с расходами или в будущем; перенос расхода на отмеченный день снимает отметку.
    @Test func dayMarkRejectsInvalidDays() async throws {
        // Хранилище теста.
        let fixture = try Fixture()
        // Расход сегодня.
        let expense = try await fixture.store.createExpense(fixture.draft(date: "2026-10-14"))
        await #expect(throws: LedgerError.dayHasExpenses) { try await fixture.store.setDayMarked(true, on: Self.today) } // День с расходом.
        await #expect(throws: LedgerError.dateInFuture) { try await fixture.store.setDayMarked(true, on: .iso("2026-10-15")) } // Завтра.

        _ = try await fixture.store.setDayMarked(true, on: .iso("2026-10-10")) // Отмечаем пустой день.
        _ = try await fixture.store.updateExpense(id: expense.id, fixture.draft(date: "2026-10-10")) // Переносим расход на него.
        #expect(try await fixture.store.dayMark(on: .iso("2026-10-10"))?.isMarked == false) // Отметка снята.
        #expect(try await fixture.store.setDayMarked(false, on: .iso("2026-10-10")).isMarked == false) // Снять можно всегда.
    }
}
