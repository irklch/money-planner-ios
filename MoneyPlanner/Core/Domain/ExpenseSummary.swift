// ExpenseSummary.swift
// Сводка расходов за период: итог, суммы и доли категорий, сегменты полосы и история по дням.
// Считается из одного набора расходов целыми копейками; без SwiftData и UI.

// Foundation нужен для UUID.
import Foundation

/// Категория расхода для отображения.
///
/// Расход ссылается на категорию UUID без FK (план §3.2). Если категории нет на устройстве
/// (например, ещё не пришла синхронизацией), расход не теряется: он попадает в итоги и историю
/// с плейсхолдером «Без категории» (план §7.3: «неизвестные → Без категории»).
nonisolated enum CategoryReference: Sendable, Hashable, Identifiable {
    /// Известная категория, в том числе архивная.
    case known(CategorySnapshot)
    /// Категории с таким UUID на устройстве нет.
    case unknown(UUID)

    /// UUID категории из расхода.
    var id: UUID {
        switch self { // UUID в обоих случаях.
        case .known(let category): category.id // UUID известной категории.
        case .unknown(let id): id // UUID из расхода.
        }
    }

    /// Это резервная категория «Другое».
    var isFallback: Bool { id == SystemCategory.fallback.id } // Сравнение с UUID реестра.
}

/// Сумма категории за период.
nonisolated struct CategoryTotal: Sendable, Hashable, Identifiable {
    /// Категория.
    let category: CategoryReference
    /// Сумма расходов категории.
    let amount: Money
    /// Число расходов категории.
    let expenseCount: Int
    /// Доля в десятых долях процента (0…1000); сумма по всем категориям ровно 1000.
    let shareTenths: Int

    /// UUID категории.
    var id: UUID { category.id } // Категория уникальна в сводке.
}

/// Сегмент составной полосы распределения («Хранилище» macOS).
nonisolated struct DistributionSegment: Sendable, Hashable, Identifiable {
    /// Вид сегмента.
    enum Kind: Sendable, Hashable {
        /// Отдельная категория.
        case category(CategoryReference)
        /// Нейтральный сегмент «Ещё N»: категории с долей < 2 %, объединённые визуально.
        case remainder(categoryCount: Int)
    }

    /// Вид сегмента.
    let kind: Kind
    /// Сумма, которую изображает сегмент; ширина пропорциональна ей.
    let amount: Money

    /// Стабильный идентификатор сегмента.
    var id: String {
        switch kind { // Идентификатор по виду.
        case .category(let category): category.id.contractString // UUID категории.
        case .remainder: "remainder" // Сегмент «Ещё N» один.
        }
    }
}

/// Расход в истории вместе с категорией.
nonisolated struct HistoryEntry: Sendable, Hashable, Identifiable {
    /// Расход.
    let expense: ExpenseSnapshot
    /// Категория расхода.
    let category: CategoryReference

    /// UUID расхода.
    var id: UUID { expense.id } // Расход уникален в истории.
}

/// Расходы одного дня в истории.
nonisolated struct HistoryDay: Sendable, Hashable, Identifiable {
    /// Календарный день.
    let date: CalendarDate
    /// Расходы дня в порядке репозитория.
    let entries: [HistoryEntry]

    /// Ключ дня.
    var id: Int { date.storageKey } // День уникален в истории.
}

/// Сводка расходов за период: все блоки экрана строятся из неё.
nonisolated struct ExpenseOverview: Sendable, Hashable {
    /// Прошедшая часть периода, по которой посчитана сводка.
    let period: ClosedRange<CalendarDate>
    /// Категория, если сводка построена для одной категории; иначе `nil`.
    let scope: CategoryReference?
    /// Итог за период.
    let total: Money
    /// Число расходов за период.
    let expenseCount: Int
    /// Категории по убыванию суммы.
    let categories: [CategoryTotal]
    /// Сегменты полосы распределения.
    let segments: [DistributionSegment]
    /// История по дням: новые дни выше.
    let days: [HistoryDay]
    /// Самая ранняя дата неудалённого расхода (в той же области); `nil`, если расходов нет совсем.
    let earliestExpenseDate: CalendarDate?

    /// В периоде нет расходов.
    var isEmpty: Bool { expenseCount == 0 } // Пустой период.
}

/// Правила полосы распределения (Figma, компонент Expense Bar `135:54`).
nonisolated enum DistributionRules {
    /// Категории с долей меньше `1 / smallShareDenominator` (2 %) объединяются в сегмент «Ещё N».
    static let smallShareDenominator: Int64 = 50
    /// Сумма долей в десятых долях процента.
    static let shareScale: Int64 = 1000
}

/// Расчёт сводки за период из одного набора расходов.
///
/// - Деньги — целые копейки, сложение с проверкой переполнения (`MoneyError.overflow`).
/// - Доли — метод наибольшего остатка в десятых долях процента, сумма ровно 100,0 %;
///   при равных остатках — большая сумма, затем `categoryId` (план §7.2).
/// - Порядок категорий — сумма ↓, затем `categoryId` ↑; полоса — тот же порядок,
///   «Другое» в конце, затем «Ещё N».
/// - Пустой набор не приводит к делению на ноль: итог 0, категорий и сегментов нет.
nonisolated enum ExpenseSummaryCalculator {
    /// Строит сводку.
    /// - Parameters:
    ///   - expenses: неудалённые расходы периода в порядке истории (дата ↓, `createdAt` ↓, UUID ↑).
    ///   - categories: известные категории по UUID, включая архивные.
    ///   - period: прошедшая часть периода.
    ///   - scopeCategoryID: категория, если сводка для одной категории.
    ///   - earliestExpenseDate: самая ранняя дата расхода в той же области.
    /// - Throws: `MoneyError.overflow`, если итог не помещается в Int64 копеек.
    static func summarize(
        expenses: [ExpenseSnapshot], // Расходы периода.
        categories: [UUID: CategorySnapshot], // Известные категории.
        period: ClosedRange<CalendarDate>, // Прошедшая часть периода.
        scopeCategoryID: UUID? = nil, // Категория области или nil.
        earliestExpenseDate: CalendarDate? = nil // Самая ранняя дата расхода.
    ) throws(MoneyError) -> ExpenseOverview {
        // Категория по UUID: известная или плейсхолдер.
        func reference(_ id: UUID) -> CategoryReference {
            categories[id].map(CategoryReference.known) ?? .unknown(id) // Неизвестная категория не теряется.
        }
        // Расходы, которые участвуют в сводке: в периоде и с положительной суммой (план §7.3).
        let counted = expenses.filter { period.contains($0.date) && $0.amount.minorUnits > 0 }

        // Итог и суммы категорий с порядком первого появления.
        var total = Money.zero
        var sums: [UUID: (amount: Money, count: Int)] = [:] // Сумма и число расходов по категории.
        for expense in counted { // Один проход по набору.
            total = try total.adding(expense.amount) // Переполнение — ошибка, а не обрезка.
            // Текущая сумма категории.
            let current = sums[expense.categoryID] ?? (Money.zero, 0)
            sums[expense.categoryID] = (try current.amount.adding(expense.amount), current.count + 1) // Сумма и счётчик.
        }

        // Категории: сумма ↓, затем UUID ↑.
        let ordered = sums
            .map { (id: $0.key, amount: $0.value.amount, count: $0.value.count) } // Пары категории и суммы.
            .sorted { lhs, rhs in // Стабильный порядок.
                lhs.amount != rhs.amount ? lhs.amount > rhs.amount : lhs.id.contractString < rhs.id.contractString // Сумма, затем UUID.
            }
        // Доли методом наибольшего остатка.
        let shares = largestRemainderShares(ordered.map { ($0.id, $0.amount) }, total: total)
        // Суммы категорий с долями.
        let categoryTotals = ordered.map { item in
            CategoryTotal(category: reference(item.id), amount: item.amount, expenseCount: item.count, shareTenths: shares[item.id] ?? 0) // Строка категории.
        }

        return ExpenseOverview( // Все блоки из одного набора.
            period: period, // Прошедшая часть периода.
            scope: scopeCategoryID.map(reference), // Категория области.
            total: total, // Итог.
            expenseCount: counted.count, // Число расходов.
            categories: categoryTotals, // Категории.
            segments: try segments(for: categoryTotals, total: total), // Полоса.
            days: historyDays(counted.map { HistoryEntry(expense: $0, category: reference($0.categoryID)) }), // История.
            earliestExpenseDate: earliestExpenseDate // Для пустого состояния.
        )
    }

    /// Доли в десятых долях процента: сумма ровно 1000 при ненулевом итоге.
    static func largestRemainderShares(_ amounts: [(id: UUID, amount: Money)], total: Money) -> [UUID: Int] {
        guard total.minorUnits > 0 else { return [:] } // Нулевой итог: делить не на что.
        // Целая часть квоты и остаток для каждой категории: amount · 1000 / total без переполнения.
        let quotas = amounts.map { item -> (id: UUID, amount: Money, floor: Int64, remainder: Int64) in
            // amount · 1000 в 128 битах.
            let product = item.amount.minorUnits.multipliedFullWidth(by: DistributionRules.shareScale)
            // Частное ≤ 1000, так как amount ≤ total.
            let (quotient, remainder) = total.minorUnits.dividingFullWidth(product)
            return (item.id, item.amount, quotient, remainder) // Квота категории.
        }
        // Нераспределённые десятые доли процента.
        var leftover = Int(DistributionRules.shareScale - quotas.reduce(0) { $0 + $1.floor })
        // Получатели добавок: остаток ↓, сумма ↓, UUID ↑.
        let byRemainder = quotas.sorted { lhs, rhs in
            if lhs.remainder != rhs.remainder { return lhs.remainder > rhs.remainder } // Больший остаток.
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount } // Большая сумма.
            return lhs.id.contractString < rhs.id.contractString // Меньший UUID.
        }
        // Итоговые доли.
        var result = Dictionary(uniqueKeysWithValues: quotas.map { ($0.id, Int($0.floor)) })
        for item in byRemainder where leftover > 0 { // По одной десятой процента первым по остатку.
            result[item.id, default: 0] += 1 // Добавка.
            leftover -= 1 // Осталось распределить.
        }
        return result // Сумма долей — 1000.
    }

    /// Сегменты полосы: категории ≥ 2 % по порядку списка, «Другое» в конце, затем «Ещё N».
    static func segments(for categories: [CategoryTotal], total: Money) throws(MoneyError) -> [DistributionSegment] {
        guard total.minorUnits > 0 else { return [] } // Пустой период: полосы нет.
        // Категория мелкая: amount / total < 1/50, проверка без деления и переполнения.
        func isSmall(_ amount: Money) -> Bool {
            // amount · 50 и признак переполнения.
            let (scaled, overflow) = amount.minorUnits.multipliedReportingOverflow(by: DistributionRules.smallShareDenominator)
            return !overflow && scaled < total.minorUnits // Переполнение означает большую сумму.
        }
        // Крупные категории без «Другое».
        var visible = categories.filter { !isSmall($0.amount) && !$0.category.isFallback }
        // «Другое», если она не мелкая, — после остальных категорий.
        visible += categories.filter { !isSmall($0.amount) && $0.category.isFallback }
        // Мелкие категории для сегмента «Ещё N».
        let small = categories.filter { isSmall($0.amount) }
        var result = visible.map { DistributionSegment(kind: .category($0.category), amount: $0.amount) } // Сегменты категорий.
        if !small.isEmpty { // Есть что объединить.
            // Сумма мелких категорий.
            var rest = Money.zero
            for item in small { rest = try rest.adding(item.amount) } // Сложение с проверкой.
            result.append(DistributionSegment(kind: .remainder(categoryCount: small.count), amount: rest)) // «Ещё N».
        }
        return result // Сегменты слева направо.
    }

    /// Группирует расходы по дням, сохраняя порядок репозитория.
    static func historyDays(_ entries: [HistoryEntry]) -> [HistoryDay] {
        var days: [HistoryDay] = [] // Готовые дни.
        var current: [HistoryEntry] = [] // Расходы текущего дня.
        for entry in entries { // Набор уже упорядочен по дате ↓.
            if let last = current.last, last.expense.date != entry.expense.date { // Начался новый день.
                days.append(HistoryDay(date: last.expense.date, entries: current)) // Закрываем предыдущий день.
                current = [] // Новый день.
            }
            current.append(entry) // Расход в текущий день.
        }
        if let last = current.last { days.append(HistoryDay(date: last.expense.date, entries: current)) } // Последний день.
        return days // Дни по убыванию даты.
    }
}
