// LedgerRepositories.swift
// Протоколы слоя данных для ViewModel: категории, расходы, отметки дня и сводка хранилища.
// Параметры и результаты — Sendable-значения; PersistentModel и ModelContext наружу не выходят.

// Foundation нужен для UUID.
import Foundation

/// Категории расходов.
protocol CategoryRepository: Sendable {
    /// Категории в порядке отображения. Архивные включаются только по запросу (история, фильтры).
    func categories(includeArchived: Bool) async throws -> [CategorySnapshot]
    /// Категория по UUID, в том числе архивная; `nil`, если её нет.
    func category(id: UUID) async throws -> CategorySnapshot?
    /// Создаёт пользовательскую категорию.
    func createCategory(_ category: NewCategory) async throws -> CategorySnapshot
    /// Меняет название, эмодзи и цвет неархивной пользовательской категории.
    func updateCategory(id: UUID, _ category: NewCategory) async throws -> CategorySnapshot
    /// Архивирует категорию. «Другое» не архивируется; разархивирование — после MVP.
    func archiveCategory(id: UUID) async throws -> CategorySnapshot
}

/// Расходы.
protocol ExpenseRepository: Sendable {
    /// Создаёт расход в неархивной категории.
    func createExpense(_ draft: ExpenseDraft) async throws -> ExpenseSnapshot
    /// Неудалённый расход по UUID; `nil`, если его нет или он удалён.
    func expense(id: UUID) async throws -> ExpenseSnapshot?
    /// Неудалённые расходы за период (границы включительно), при необходимости — одной категории.
    ///
    /// Порядок: дата ↓, момент создания ↓, UUID ↑ — стабилен при одинаковых датах.
    func expenses(in period: ClosedRange<CalendarDate>, categoryID: UUID?) async throws -> [ExpenseSnapshot]
    /// Меняет сумму, категорию, дату и комментарий расхода.
    func updateExpense(id: UUID, _ draft: ExpenseDraft) async throws -> ExpenseSnapshot
    /// Удаляет расход: запись становится tombstone и исчезает из истории.
    func deleteExpense(id: UUID) async throws
}

/// Отметки «День без расходов».
protocol DayMarkRepository: Sendable {
    /// Отметка дня; `nil`, если её никогда не ставили.
    func dayMark(on date: CalendarDate) async throws -> DayMarkSnapshot?
    /// Ставит или снимает отметку дня.
    func setDayMarked(_ isMarked: Bool, on date: CalendarDate) async throws -> DayMarkSnapshot
}

/// Сводка расходов за период для главного экрана и экрана категории.
protocol ExpenseOverviewProviding: Sendable {
    /// Сводка неудалённых расходов за период (границы включительно), при необходимости — одной категории.
    ///
    /// Итог, категории, полоса и история посчитаны из одного набора расходов. Архивные категории
    /// участвуют, расходы без категории на устройстве попадают в «Без категории».
    func overview(of period: ClosedRange<CalendarDate>, categoryID: UUID?) async throws -> ExpenseOverview
}

/// Оповещения об изменении локальных данных.
protocol LedgerChangeObserving: Sendable {
    /// Поток событий «данные изменились»; подписка живёт, пока не отменена задача-подписчик.
    func changes() -> AsyncStream<Void>
}

/// Подготовка локального хранилища и сводка его содержимого.
protocol LedgerSummaryProviding: Sendable {
    /// Создаёт недостающие системные категории и возвращает сводку.
    func prepare() async throws -> LedgerSummary
}
