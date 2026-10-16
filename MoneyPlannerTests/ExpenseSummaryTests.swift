// ExpenseSummaryTests.swift
// Тесты расчёта сводки и периодов: точные суммы, доли, порядок, полоса, переполнение, границы.

// Foundation нужен для UUID и Date.
import Foundation
// Testing нужен для @Suite, @Test и #expect.
import Testing
// Доступ к внутренним типам приложения.
@testable import MoneyPlanner

/// Тесты `ExpenseSummaryCalculator`.
@Suite("ExpenseSummaryCalculator")
struct ExpenseSummaryCalculatorTests {
    /// Период тестов: сентябрь 2026.
    private let september = CalendarDate.iso("2026-09-01")...CalendarDate.iso("2026-09-30")

    /// Снимок расхода для расчёта.
    private func expense(_ minor: Int64, _ category: UUID, _ date: String = "2026-09-15", comment: String? = nil, created: TimeInterval = 0) -> ExpenseSnapshot {
        ExpenseSnapshot( // Поля снимка.
            id: UUID(), amount: Money(minorUnits: minor), categoryID: category, date: .iso(date), comment: comment, // Данные расхода.
            createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: created) // Моменты.
        )
    }

    /// Снимок системной категории (возможно, архивной).
    private func category(_ system: SystemCategory, archived: Bool = false) -> CategorySnapshot {
        CategorySnapshot( // Поля снимка.
            id: system.id, kind: .system, title: .system(system), emoji: system.emoji, colorIndex: system.colorIndex, // Реестр.
            sortOrder: system.sortOrder, isArchived: archived, isArchivable: system.isArchivable // Состояние.
        )
    }

    /// Словарь известных категорий.
    private func known(_ items: [CategorySnapshot]) -> [UUID: CategorySnapshot] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }) // По UUID.
    }

    @Test func emptyPeriodHasZeroTotalAndNoDivision() throws {
        // Сводка без расходов.
        let overview = try ExpenseSummaryCalculator.summarize(expenses: [], categories: [:], period: september)
        #expect(overview.total == .zero)
        #expect(overview.isEmpty)
        #expect(overview.categories.isEmpty)
        #expect(overview.segments.isEmpty)
        #expect(overview.days.isEmpty)
        #expect(ExpenseSummaryCalculator.largestRemainderShares([], total: .zero).isEmpty)
    }

    @Test func exactTotalsAndSharesFromOneSet() throws {
        // Три категории с суммами 500,01 / 300,33 / 199,66 ₽.
        let expenses = [
            expense(30_033, SystemCategory.cafe.id), expense(25_000, SystemCategory.products.id),
            expense(19_966, SystemCategory.transport.id), expense(25_001, SystemCategory.products.id),
        ]
        // Сводка.
        let overview = try ExpenseSummaryCalculator.summarize(
            expenses: expenses, categories: known([category(.products), category(.cafe), category(.transport)]), period: september
        )
        #expect(overview.total == Money(minorUnits: 100_000))
        #expect(overview.categories.map(\.amount.minorUnits) == [50_001, 30_033, 19_966])
        #expect(overview.categories.map(\.expenseCount) == [2, 1, 1])
        // Сумма категорий равна итогу.
        #expect(overview.categories.reduce(0) { $0 + $1.amount.minorUnits } == overview.total.minorUnits)
        // 500,01 = 50,001 % → 500; 300,33 = 30,033 % → 300; 199,66 = 19,966 % → 199 + 1 по наибольшему остатку.
        #expect(overview.categories.map(\.shareTenths) == [500, 300, 200])
    }

    @Test func largestRemainderAlwaysSumsTo1000AndBreaksTiesByAmountThenID() throws {
        // Три равные категории: по 333 и одна добавка — меньшему UUID.
        let ids = [UUID(), UUID(), UUID()].sorted { $0.contractString < $1.contractString }
        let equal = ExpenseSummaryCalculator.largestRemainderShares(ids.map { ($0, Money(minorUnits: 100)) }, total: Money(minorUnits: 300))
        #expect(equal.values.reduce(0, +) == 1000)
        #expect(equal[ids[0]] == 334)
        #expect(equal[ids[1]] == 333 && equal[ids[2]] == 333)
        // Много мелких категорий: сумма всё равно ровно 100,0 %.
        let many = (0..<37).map { (UUID(), Money(minorUnits: Int64($0 + 1) * 7)) }
        let total = Money(minorUnits: many.reduce(0) { $0 + $1.1.minorUnits })
        #expect(ExpenseSummaryCalculator.largestRemainderShares(many, total: total).values.reduce(0, +) == 1000)
    }

    @Test func stableOrderForEqualAmounts() throws {
        // Равные суммы в разных категориях, порядок входа — разный.
        let input = [expense(1_000, SystemCategory.travel.id), expense(1_000, SystemCategory.cafe.id), expense(1_000, SystemCategory.products.id)]
        // Две сводки по переставленному набору.
        let first = try ExpenseSummaryCalculator.summarize(expenses: input, categories: [:], period: september)
        let second = try ExpenseSummaryCalculator.summarize(expenses: input.reversed(), categories: [:], period: september)
        #expect(first.categories.map(\.id) == second.categories.map(\.id))
        #expect(first.categories.map(\.id) == [SystemCategory.products.id, SystemCategory.cafe.id, SystemCategory.travel.id]) // UUID ↑.
        #expect(first.segments.map(\.id) == second.segments.map(\.id))
    }

    @Test func archivedAndUnknownCategoriesKeepTheirMoney() throws {
        // Расход в неизвестной категории.
        let missing = UUID()
        // Сводка с архивной и неизвестной категориями.
        let overview = try ExpenseSummaryCalculator.summarize(
            expenses: [expense(70_000, SystemCategory.gifts.id), expense(30_000, missing, comment: "Перевод")],
            categories: known([category(.gifts, archived: true)]), period: september
        )
        #expect(overview.total == Money(minorUnits: 100_000))
        #expect(overview.categories.first?.category == .known(category(.gifts, archived: true)))
        #expect(overview.categories.last?.category == .unknown(missing))
        #expect(overview.days.first?.entries.contains { $0.category == .unknown(missing) } == true)
    }

    @Test func periodBoundariesAreInclusive() throws {
        // Расходы на границах и за ними, в порядке репозитория (дата ↓).
        let expenses = [
            expense(400, SystemCategory.cafe.id, "2026-10-01"), expense(300, SystemCategory.cafe.id, "2026-09-30"),
            expense(200, SystemCategory.cafe.id, "2026-09-01"), expense(100, SystemCategory.cafe.id, "2026-08-31"),
        ]
        // Сводка за сентябрь.
        let overview = try ExpenseSummaryCalculator.summarize(expenses: expenses, categories: [:], period: september)
        #expect(overview.total == Money(minorUnits: 500))
        #expect(overview.days.map(\.date) == [.iso("2026-09-30"), .iso("2026-09-01")])
    }

    @Test func overflowIsReportedNotWrapped() {
        // Два расхода, сумма которых не помещается в Int64.
        let huge = [expense(Int64.max / 2 + 1, SystemCategory.cafe.id), expense(Int64.max / 2 + 1, SystemCategory.products.id)]
        #expect(throws: MoneyError.overflow) {
            try ExpenseSummaryCalculator.summarize(expenses: huge, categories: [:], period: september)
        }
    }

    @Test func barMergesSmallCategoriesAndPutsFallbackLast() throws {
        // «Другое» 30 %, продукты 60 %, две мелкие категории по 1 %, кафе 8 %.
        let expenses = [
            expense(3_000, SystemCategory.other.id), expense(6_000, SystemCategory.products.id), expense(800, SystemCategory.cafe.id),
            expense(100, SystemCategory.travel.id), expense(100, SystemCategory.gifts.id),
        ]
        // Сводка.
        let overview = try ExpenseSummaryCalculator.summarize(expenses: expenses, categories: [:], period: september)
        // Порядок сегментов.
        let kinds = overview.segments.map(\.kind)
        #expect(kinds.count == 4)
        #expect(kinds[0] == .category(.unknown(SystemCategory.products.id)))
        #expect(kinds[1] == .category(.unknown(SystemCategory.cafe.id)))
        #expect(kinds[2] == .category(.unknown(SystemCategory.other.id)))
        #expect(kinds[3] == .remainder(categoryCount: 2))
        #expect(overview.segments.reduce(0) { $0 + $1.amount.minorUnits } == overview.total.minorUnits)
        // Список показывает все категории отдельно.
        #expect(overview.categories.count == 5)
    }

    @Test func exactlyTwoPercentIsNotMerged() throws {
        // 2 % ровно и чуть меньше 2 %.
        let expenses = [expense(9_799, SystemCategory.products.id), expense(200, SystemCategory.cafe.id), expense(1, SystemCategory.travel.id)]
        // Сводка: итог 10 000 копеек.
        let overview = try ExpenseSummaryCalculator.summarize(expenses: expenses, categories: [:], period: september)
        #expect(overview.segments.map(\.kind) == [
            .category(.unknown(SystemCategory.products.id)), .category(.unknown(SystemCategory.cafe.id)), .remainder(categoryCount: 1),
        ])
    }

    @Test func historyGroupsByDayKeepingRepositoryOrder() throws {
        // Порядок репозитория: дата ↓, создание ↓.
        let a = expense(100, SystemCategory.cafe.id, "2026-09-20", created: 30)
        let b = expense(200, SystemCategory.cafe.id, "2026-09-20", created: 20)
        let c = expense(300, SystemCategory.cafe.id, "2026-09-02", created: 50)
        // Сводка.
        let overview = try ExpenseSummaryCalculator.summarize(expenses: [a, b, c], categories: [:], period: september)
        #expect(overview.days.count == 2)
        #expect(overview.days[0].entries.map(\.id) == [a.id, b.id])
        #expect(overview.days[1].entries.map(\.id) == [c.id])
    }
}

/// Тесты `ExpensePeriod`.
@Suite("ExpensePeriod")
struct ExpensePeriodTests {
    @Test func currentMonthElapsedEndsToday() {
        // Текущий месяц на 15 октября.
        let period = ExpensePeriod(preset: .currentMonth, today: .iso("2026-10-15"))
        #expect(period.interval == CalendarDate.iso("2026-10-01")...CalendarDate.iso("2026-10-31"))
        #expect(period.elapsed == CalendarDate.iso("2026-10-01")...CalendarDate.iso("2026-10-15"))
    }

    @Test func previousMonthCrossesYearAndLeapFebruary() {
        #expect(ExpensePeriod(preset: .previousMonth, today: .iso("2027-01-10")).interval == CalendarDate.iso("2026-12-01")...CalendarDate.iso("2026-12-31"))
        // Март високосного года → февраль из 29 дней; прошлый месяц полный.
        let february = ExpensePeriod(preset: .previousMonth, today: .iso("2024-03-31"))
        #expect(february.interval == CalendarDate.iso("2024-02-01")...CalendarDate.iso("2024-02-29"))
        #expect(february.elapsed == february.interval)
    }

    @Test func rollingWindowsIncludeToday() {
        // 30 и 90 дней на 30 сентября — как в макете D3: «1–30 сен», «3 июл – 30 сен».
        #expect(ExpensePeriod(preset: .last30Days, today: .iso("2026-09-30")).interval == CalendarDate.iso("2026-09-01")...CalendarDate.iso("2026-09-30"))
        #expect(ExpensePeriod(preset: .last90Days, today: .iso("2026-09-30")).interval == CalendarDate.iso("2026-07-03")...CalendarDate.iso("2026-09-30"))
    }

    @Test func timeZoneOnlyChangesWhichDayIsToday() {
        // Один и тот же момент: в Москве уже 1 октября, в Лос-Анджелесе ещё 30 сентября.
        let instant = Date(timeIntervalSince1970: 1_790_805_600) // 2026-09-30 22:00 UTC.
        let moscow = ExpensePeriod(preset: .currentMonth, today: .today(in: TimeZone(identifier: "Europe/Moscow")!, now: instant))
        let losAngeles = ExpensePeriod(preset: .currentMonth, today: .today(in: TimeZone(identifier: "America/Los_Angeles")!, now: instant))
        #expect(moscow.interval.lowerBound == .iso("2026-10-01"))
        #expect(losAngeles.interval.lowerBound == .iso("2026-09-01"))
        // Расход 30 сентября остаётся 30 сентября: он в сентябрьском периоде, а не в октябрьском.
        #expect(losAngeles.elapsed.contains(.iso("2026-09-30")))
        #expect(!moscow.elapsed.contains(.iso("2026-09-30")))
    }
}
