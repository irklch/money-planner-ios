// LedgerSnapshots.swift
// Sendable-снимки и черновики расходов, категорий и отметок дня для ViewModel.
// Не зависят от SwiftData и сетевых DTO.

// Foundation нужен для UUID и Date.
import Foundation

/// Вид категории (`kind` контракта).
nonisolated enum CategoryKind: String, Sendable, Hashable {
    /// Системная категория из реестра; определение — константа приложения.
    case system
    /// Пользовательская категория.
    case user
}

/// Название категории для отображения.
nonisolated enum CategoryTitle: Sendable, Hashable {
    /// Системная категория: название из String Catalog (`SystemCategory.name`).
    case system(SystemCategory)
    /// Пользовательская категория: название как ввёл пользователь.
    case user(String)
}

/// Снимок категории.
nonisolated struct CategorySnapshot: Sendable, Hashable, Identifiable {
    /// Стабильный UUID категории.
    let id: UUID
    /// Вид категории.
    let kind: CategoryKind
    /// Название для отображения.
    let title: CategoryTitle
    /// Эмодзи категории.
    let emoji: String
    /// Индекс цвета `CategoryPalette` (0–11).
    let colorIndex: Int
    /// Порядок в списке.
    let sortOrder: Int
    /// Категория архивирована: остаётся в истории, недоступна для новых расходов.
    let isArchived: Bool
    /// Можно ли архивировать (все, кроме «Другое»).
    let isArchivable: Bool
}

/// Данные новой пользовательской категории.
nonisolated struct NewCategory: Sendable, Hashable {
    /// Название (1–24 Unicode scalar values после нормализации).
    var name: String
    /// Эмодзи (одна графема).
    var emoji: String
    /// Индекс цвета `CategoryPalette` (0–11).
    var colorIndex: Int
}

/// Снимок расхода.
nonisolated struct ExpenseSnapshot: Sendable, Hashable, Identifiable {
    /// Стабильный UUID расхода.
    let id: UUID
    /// Сумма.
    let amount: Money
    /// UUID категории. Связь сохраняется, даже если категория архивирована или ещё не загружена.
    let categoryID: UUID
    /// Календарный день расхода.
    let date: CalendarDate
    /// Нормализованный комментарий; `nil` — без комментария.
    let comment: String?
    /// Момент создания (часы устройства).
    let createdAt: Date
    /// Момент последнего изменения (часы устройства).
    let updatedAt: Date
}

/// Поля расхода, которые задаёт пользователь при создании и изменении.
///
/// Ручные и импортированные расходы — одна сущность (архитектура §8.1): после сохранения
/// у них одинаковый набор редактируемых полей. Отдельного поля названия нет: название
/// операции из выписки хранится в `comment`.
nonisolated struct ExpenseDraft: Sendable, Hashable {
    /// Сумма (0.01 … 999 999 999.99 ₽).
    var amount: Money
    /// UUID категории. Для нового расхода категория должна существовать и не быть архивной.
    var categoryID: UUID
    /// Календарный день расхода.
    var date: CalendarDate
    /// Комментарий; нормализуется и проверяется (≤ 200 Unicode scalar values).
    var comment: String?
}

/// Снимок отметки «День без расходов».
nonisolated struct DayMarkSnapshot: Sendable, Hashable {
    /// Календарный день.
    let date: CalendarDate
    /// Отметка поставлена.
    let isMarked: Bool
}

/// Сводка локального хранилища для временного экрана запуска.
nonisolated struct LedgerSummary: Sendable, Hashable {
    /// Число категорий, доступных для новых расходов.
    let activeCategoryCount: Int
    /// Число неудалённых расходов.
    let expenseCount: Int
}

/// Ошибка операции с расходами, категориями и отметками дня.
///
/// Ошибки проверки данных выбрасываются до записи. Ошибки SwiftData пробрасываются
/// без изменений после отката контекста.
nonisolated enum LedgerError: Error, Sendable, Equatable {
    /// Запись не найдена или удалена.
    case notFound
    /// Категория не найдена.
    case categoryNotFound
    /// Категория архивирована: новые расходы и перенос расходов в неё запрещены.
    case categoryArchived
    /// Системную категорию нельзя изменять (кроме архивирования).
    case systemCategoryNotEditable
    /// Категория не архивируется («Другое»).
    case categoryNotArchivable
    /// Сумма вне диапазона 0.01 … 999 999 999.99.
    case invalidAmount
    /// Комментарий длиннее 200 Unicode scalar values.
    case commentTooLong
    /// Название категории пустое или длиннее 24 Unicode scalar values.
    case invalidCategoryName
    /// Эмодзи — не одна графема.
    case invalidEmoji
    /// Индекс цвета вне 0–11.
    case invalidColorIndex
    /// На дату есть расходы: её нельзя отметить как день без расходов.
    case dayHasExpenses
    /// Дата в будущем.
    case dateInFuture
}
