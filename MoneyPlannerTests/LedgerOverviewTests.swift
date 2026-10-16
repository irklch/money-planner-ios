// LedgerOverviewTests.swift
// Тесты сводки из хранилища: чтение только периода, удалённые расходы, архивные и неизвестные категории,
// оповещения об изменениях и фактический исполнитель хранилища.

// Foundation нужен для Date, UUID и Thread.
import Foundation
// SwiftData нужен для ModelContext.
import SwiftData
// Testing нужен для @Suite, @Test и #expect.
import Testing
// Доступ к внутренним типам приложения.
@testable import MoneyPlanner

extension LedgerStore {
    /// Выполняется ли метод актора на главном потоке (проверка фактического исполнителя).
    func isRunningOnMainThread() -> Bool {
        Thread.isMainThread // Поток, на котором исполнитель выполняет работу актора.
    }
}

/// Тесты `LedgerStore.overview` и `changeFeed`.
@MainActor
@Suite("LedgerStore overview")
struct LedgerOverviewTests {
    /// Хранилище поверх новой БД в памяти, созданное так же, как в приложении.
    private func makeStore() async throws -> (LedgerStore, ModelContainer) {
        // Изолированная БД.
        let container = try ModelContainerFactory.makeInMemory()
        return (LedgerStore(container: container), container) // Так же, как в AppDependencies.
    }

    /// Черновик расхода.
    private func draft(_ amount: String, _ category: SystemCategory, _ date: String, comment: String? = nil) -> ExpenseDraft {
        ExpenseDraft(amount: .api(amount), categoryID: category.id, date: .iso(date), comment: comment) // Черновик из строк.
    }

    @Test func storeDoesNotRunOnMainThread() async throws {
        // Хранилище, созданное на MainActor, как в приложении.
        let (store, _) = try await makeStore()
        #expect(await store.isRunningOnMainThread() == false) // Чтение и расчёт не блокируют MainActor.
    }

    @Test func overviewUsesOnlyLiveExpensesOfThePeriod() async throws {
        // Хранилище.
        let (store, _) = try await makeStore()
        _ = try await store.createExpense(draft("100.00", .cafe, "2026-08-31")) // До периода.
        _ = try await store.createExpense(draft("200.00", .cafe, "2026-09-01")) // Первый день.
        _ = try await store.createExpense(draft("300.50", .products, "2026-09-30", comment: "Ужин")) // Последний день.
        // Расход, который удалят.
        let deleted = try await store.createExpense(draft("999.00", .products, "2026-09-15"))
        try await store.deleteExpense(id: deleted.id) // Tombstone.
        _ = try await store.createExpense(draft("400.00", .cafe, "2026-10-01")) // После периода.
        // Сводка за сентябрь.
        let overview = try await store.overview(of: .iso("2026-09-01")...(.iso("2026-09-30")), categoryID: nil)
        #expect(overview.total == .api("500.50"))
        #expect(overview.expenseCount == 2)
        #expect(overview.days.map(\.date) == [.iso("2026-09-30"), .iso("2026-09-01")])
        #expect(overview.categories.map(\.id) == [SystemCategory.products.id, SystemCategory.cafe.id])
        #expect(overview.earliestExpenseDate == nil) // Нужна только пустому периоду.
        // Сводка одной категории за тот же период.
        let cafe = try await store.overview(of: .iso("2026-09-01")...(.iso("2026-09-30")), categoryID: SystemCategory.cafe.id)
        #expect(cafe.total == .api("200.00"))
        #expect(cafe.scope?.id == SystemCategory.cafe.id)
    }

    @Test func archivedAndMissingCategoriesStayInTotalsAndHistory() async throws {
        // Хранилище и контейнер.
        let (store, container) = try await makeStore()
        // Своя категория, которую архивируют.
        let pool = try await store.createCategory(NewCategory(name: "Бассейн", emoji: "🏊", colorIndex: 6))
        _ = try await store.createExpense(ExpenseDraft(amount: .api("700.00"), categoryID: pool.id, date: .iso("2026-09-10"), comment: nil))
        _ = try await store.archiveCategory(id: pool.id) // Архив после расхода.
        // Расход категории, которой нет на устройстве (как его применил бы sync).
        let missing = UUID()
        let context = ModelContext(container) // Отдельный контекст той же БД.
        context.insert(Expense(id: UUID(), amountMinorUnits: 30_000, categoryID: missing, dateKey: CalendarDate.iso("2026-09-11").storageKey, comment: nil, now: .now))
        try context.save() // Запись.
        // Сводка за сентябрь.
        let overview = try await store.overview(of: .iso("2026-09-01")...(.iso("2026-09-30")), categoryID: nil)
        #expect(overview.total == .api("1000.00"))
        #expect(overview.categories.map(\.category.id) == [pool.id, missing])
        guard case .known(let archived) = overview.categories[0].category else { Issue.record("Archived category is unknown"); return }
        #expect(archived.isArchived)
        #expect(overview.categories[1].category == .unknown(missing))
        // Архивная категория открывается: сводка по ней есть.
        let poolOverview = try await store.overview(of: .iso("2026-09-01")...(.iso("2026-09-30")), categoryID: pool.id)
        #expect(poolOverview.total == .api("700.00"))
        #expect(poolOverview.scope == .known(archived))
    }

    @Test func emptyPeriodReportsEarliestExpense() async throws {
        // Хранилище.
        let (store, _) = try await makeStore()
        _ = try await store.createExpense(draft("100.00", .cafe, "2026-09-01")) // Первый расход — в сентябре.
        _ = try await store.createExpense(draft("100.00", .cafe, "2026-09-20")) // Ещё один.
        // Пустой август.
        let august = try await store.overview(of: .iso("2026-08-01")...(.iso("2026-08-31")), categoryID: nil)
        #expect(august.isEmpty)
        #expect(august.total == .zero)
        #expect(august.earliestExpenseDate == .iso("2026-09-01"))
        // Пустая категория без расходов вообще.
        let travel = try await store.overview(of: .iso("2026-08-01")...(.iso("2026-08-31")), categoryID: SystemCategory.travel.id)
        #expect(travel.earliestExpenseDate == nil)
    }

    @Test func changeFeedNotifiesAfterSavedChange() async throws {
        // Хранилище.
        let (store, _) = try await makeStore()
        _ = try await store.overview(of: .iso("2026-09-01")...(.iso("2026-09-30")), categoryID: nil) // Подготовка категорий без оповещения.
        // Подписка.
        let stream = store.changes()
        var iterator = stream.makeAsyncIterator() // Читатель событий.
        _ = try await store.createExpense(draft("10.00", .cafe, "2026-09-02")) // Сохранённое изменение.
        #expect(await iterator.next() != nil) // Событие получено.
        #expect(store.changeFeed.subscriberCount == 1)
    }

    @Test func cancelledSubscriberIsRemoved() async throws {
        // Хранилище.
        let (store, _) = try await makeStore()
        // Задача-подписчик.
        let subscriber = Task { for await _ in store.changes() {} }
        for _ in 0..<1_000 where store.changeFeed.subscriberCount == 0 { await Task.yield() } // Подписка началась.
        #expect(store.changeFeed.subscriberCount == 1)
        subscriber.cancel() // Уход с экрана.
        await subscriber.value // Подписчик завершился.
        #expect(store.changeFeed.subscriberCount == 0)
    }
}
