// ExpenseOverviewModelTests.swift
// Тесты ViewModel сводки: устаревшие ответы, ошибка и повтор, обновление без сброса периода, отмена.

// Foundation нужен для UUID.
import Foundation
// Synchronization нужен для Mutex в управляемом репозитории.
import Synchronization
// Testing нужен для @Suite, @Test и #expect.
import Testing
// Доступ к внутренним типам приложения.
@testable import MoneyPlanner

/// Репозиторий, ответами которого управляет тест.
///
/// Каждый вызов ждёт, пока тест не выдаст ответ для него (`respond`), поэтому можно
/// воспроизвести любой порядок завершения запросов.
private final class ControlledOverviewRepository: ExpenseOverviewProviding {
    /// Ожидающие вызовы и уже выданные ответы по номеру вызова.
    private let state = Mutex((pending: [Int: CheckedContinuation<ExpenseOverview, any Error>](), ready: [Int: Result<ExpenseOverview, any Error>](), calls: [ClosedRange<CalendarDate>]()))

    /// Периоды вызовов по порядку.
    var calls: [ClosedRange<CalendarDate>] { state.withLock { $0.calls } }

    /// Ждёт ответа теста для своего номера вызова.
    func overview(of period: ClosedRange<CalendarDate>, categoryID: UUID?) async throws -> ExpenseOverview {
        try await withCheckedThrowingContinuation { continuation in // Ответ выдаст тест.
            // Готовый ответ, если тест выдал его заранее.
            let ready = state.withLock { state -> Result<ExpenseOverview, any Error>? in
                let index = state.calls.count // Номер этого вызова.
                state.calls.append(period) // Запоминаем период.
                if let result = state.ready.removeValue(forKey: index) { return result } // Ответ уже есть.
                state.pending[index] = continuation // Ждём ответа.
                return nil // Ответа пока нет.
            }
            if let ready { continuation.resume(with: ready) } // Сразу отвечаем.
        }
    }

    /// Выдаёт ответ вызову с номером `index`.
    func respond(_ index: Int, with result: Result<ExpenseOverview, any Error>) {
        // Ожидающий вызов, если он уже начался.
        let continuation = state.withLock { state -> CheckedContinuation<ExpenseOverview, any Error>? in
            guard let waiting = state.pending.removeValue(forKey: index) else { state.ready[index] = result; return nil } // Ответ на будущее.
            return waiting // Вызов ждёт.
        }
        continuation?.resume(with: result) // Возобновляем вызов.
    }

    /// Ждёт, пока число вызовов не станет `count` (ограниченно, чтобы тест не зависал).
    func waitForCalls(_ count: Int) async {
        for _ in 0..<100_000 where state.withLock({ $0.calls.count }) < count { await Task.yield() } // Кооперативное ожидание.
        #expect(state.withLock { $0.calls.count } >= count, "Repository was not called \(count) times") // Вызовы состоялись.
    }
}

/// Ошибка чтения в тестах.
private struct ReadFailure: Error {}

/// Тесты `ExpenseOverviewModel`.
@MainActor
@Suite("ExpenseOverviewModel")
struct ExpenseOverviewModelTests {
    /// «Сегодня» тестов.
    private let today = CalendarDate.iso("2026-10-15")

    /// Сводка с итогом `minor` за период.
    private func overview(_ minor: Int64, period: ExpensePeriod) throws -> ExpenseOverview {
        try ExpenseSummaryCalculator.summarize( // Сводка из одного расхода.
            expenses: [ExpenseSnapshot(id: UUID(), amount: Money(minorUnits: minor), categoryID: SystemCategory.cafe.id, date: period.elapsed.upperBound, comment: nil, createdAt: .now, updatedAt: .now)],
            categories: [:], period: period.elapsed // Без известных категорий.
        )
    }

    /// ViewModel с управляемым репозиторием.
    private func makeModel(_ repository: ControlledOverviewRepository, feed: LedgerChangeFeed = LedgerChangeFeed(), selection: PeriodSelection = PeriodSelection()) -> ExpenseOverviewModel {
        ExpenseOverviewModel(selection: selection, repository: repository, changes: FeedObserver(feed: feed), today: { [today] in today }) // Фиксированное «сегодня».
    }

    @Test func lateResponseOfOldPeriodDoesNotReplaceNewOne() async throws {
        // Репозиторий, ответы которого выдаёт тест.
        let repository = ControlledOverviewRepository()
        // ViewModel.
        let model = makeModel(repository)
        model.select(.previousMonth) // Запрос 0 — прошлый месяц.
        model.select(.last30Days) // Запрос 1 — 30 дней.
        await repository.waitForCalls(2) // Оба запроса начались.
        // Периоды запросов.
        let old = ExpensePeriod(preset: .previousMonth, today: today)
        let new = ExpensePeriod(preset: .last30Days, today: today)
        repository.respond(1, with: .success(try overview(3_000, period: new))) // Новый ответ приходит первым.
        try await waitUntil { model.overview?.total == Money(minorUnits: 3_000) } // Новый период показан.
        repository.respond(0, with: .success(try overview(1_000, period: old))) // Поздний ответ старого периода.
        await settle() // Даём позднему ответу примениться, если бы он мог.
        #expect(model.overview?.total == Money(minorUnits: 3_000)) // Старый ответ отброшен.
        #expect(model.preset == .last30Days)
        #expect(model.overview?.period == new.elapsed)
    }

    @Test func failureShowsErrorAndRetryLoads() async throws {
        // Репозиторий, ответы которого выдаёт тест.
        let repository = ControlledOverviewRepository()
        // ViewModel.
        let model = makeModel(repository)
        // Период по умолчанию.
        let period = ExpensePeriod(preset: .initial, today: today)
        repository.respond(0, with: .failure(ReadFailure())) // Первое чтение падает.
        await model.reload().value // Загрузка.
        #expect(model.phase == .failed) // Ошибка, а не «расходов нет».
        repository.respond(1, with: .success(try overview(500, period: period))) // Повтор успешен.
        model.retry() // Повтор.
        try await waitUntil { model.overview != nil } // Данные пришли.
        #expect(model.overview?.total == Money(minorUnits: 500))
    }

    @Test func dataChangeRefreshesWithoutResettingPeriod() async throws {
        // Репозиторий, ответы которого выдаёт тест.
        let repository = ControlledOverviewRepository()
        // Рассылка изменений.
        let feed = LedgerChangeFeed()
        // ViewModel.
        let model = makeModel(repository, feed: feed)
        // Выбранный период.
        let period = ExpensePeriod(preset: .last90Days, today: today)
        model.select(.last90Days) // Пользователь выбрал 90 дней.
        repository.respond(0, with: .success(try overview(100, period: period))) // Первая сводка.
        // Экран показан: загрузка и подписка.
        let screen = Task { await model.run() }
        try await waitUntil { feed.subscriberCount == 1 && model.overview?.total == Money(minorUnits: 100) } // Подписка активна.
        await repository.waitForCalls(2) // `run()` перечитал данные при появлении экрана.
        repository.respond(1, with: .success(try overview(100, period: period))) // Ответ на появление.
        try await waitUntil { !model.isRefreshing } // Чтение завершено.
        feed.notify() // Расход создан, изменён или удалён.
        await repository.waitForCalls(3) // Перечитывание по событию.
        #expect(model.isRefreshing) // Обновление идёт…
        #expect(model.overview?.total == Money(minorUnits: 100)) // …а прежние данные остаются на экране.
        repository.respond(2, with: .success(try overview(250, period: period))) // Новые данные.
        try await waitUntil { model.overview?.total == Money(minorUnits: 250) } // Обновлено.
        #expect(model.preset == .last90Days) // Период не сброшен.
        #expect(repository.calls.allSatisfy { $0 == period.elapsed }) // Все чтения — за выбранный период.
        screen.cancel() // Уход с экрана.
        try await waitUntil { feed.subscriberCount == 0 } // Подписка снята.
    }

    @Test func periodChangedElsewhereIsPickedUp() async throws {
        // Репозиторий, ответы которого выдаёт тест.
        let repository = ControlledOverviewRepository()
        // Общий период двух экранов.
        let selection = PeriodSelection()
        // Главный экран и экран категории.
        let home = makeModel(repository, selection: selection)
        let category = ExpenseOverviewModel(categoryID: SystemCategory.cafe.id, selection: selection, repository: repository, changes: FeedObserver(feed: LedgerChangeFeed()), today: { [today] in today })
        repository.respond(0, with: .success(try overview(1, period: ExpensePeriod(preset: .initial, today: today)))) // Главный экран загружен.
        await home.reload().value // Загрузка.
        category.select(.previousMonth) // Период сменили на экране категории.
        home.syncWithSelection() // Возврат на главный экран.
        await repository.waitForCalls(3) // Главный экран перечитал данные.
        #expect(repository.calls.last == ExpensePeriod(preset: .previousMonth, today: today).elapsed)
    }

    /// Ждёт условие, уступая исполнитель.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 where !condition() { await Task.yield() } // Ограниченное ожидание.
        #expect(condition()) // Условие выполнено.
    }

    /// Даёт отложенным задачам выполниться.
    private func settle() async {
        for _ in 0..<200 { await Task.yield() } // Несколько циклов исполнителя.
    }
}

/// Наблюдатель изменений поверх рассылки.
private struct FeedObserver: LedgerChangeObserving {
    /// Рассылка.
    let feed: LedgerChangeFeed

    /// Поток событий рассылки.
    func changes() -> AsyncStream<Void> { feed.changes() } // Подписка.
}
