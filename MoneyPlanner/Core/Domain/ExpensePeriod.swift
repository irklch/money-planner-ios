// ExpensePeriod.swift
// Варианты периода главного экрана и их календарные границы.
// Правила — Figma D3 «Выбор периода» и план миграции бэкенда §7.3.

/// Вариант периода — единственный глобальный фильтр (Figma D3, узел `295:6198`).
///
/// Произвольных дат нет. Начальное значение — текущий месяц; между запусками не сохраняется.
nonisolated enum PeriodPreset: String, CaseIterable, Sendable, Hashable {
    /// Текущий календарный месяц.
    case currentMonth
    /// Прошлый календарный месяц.
    case previousMonth
    /// Последние 30 дней, включая сегодня.
    case last30Days
    /// Последние 90 дней, включая сегодня.
    case last90Days

    /// Период при открытии приложения.
    static let initial = PeriodPreset.currentMonth

    /// Число дней скользящего периода; `nil` для календарного месяца.
    var rollingDayCount: Int? {
        switch self { // Длина зависит от варианта.
        case .currentMonth, .previousMonth: nil // Месяц — календарный.
        case .last30Days: 30 // 30 дней.
        case .last90Days: 90 // 90 дней.
        }
    }
}

/// Период с конкретными календарными границами на дату «сегодня».
///
/// Границы включительные и основаны на `CalendarDate`, поэтому смена часового пояса
/// не переносит расходы на соседний день: пояс влияет только на то, какой день «сегодня».
nonisolated struct ExpensePeriod: Sendable, Hashable {
    /// Вариант периода.
    let preset: PeriodPreset
    /// Полный период `P = [a, b]`.
    let interval: ClosedRange<CalendarDate>
    /// Прошедшая часть `P* = [a, min(b, сегодня)]`: по ней считаются итоги и история (план §7.3).
    let elapsed: ClosedRange<CalendarDate>

    /// Вычисляет границы варианта на дату `today`.
    init(preset: PeriodPreset, today: CalendarDate) {
        self.preset = preset // Вариант периода.
        // Полный период.
        let interval: ClosedRange<CalendarDate>
        switch preset { // Границы зависят от варианта.
        case .currentMonth: // Месяц, в который попадает сегодня.
            interval = Self.month(year: today.year, month: today.month) // Весь текущий месяц.
        case .previousMonth: // Предыдущий календарный месяц.
            interval = today.month == 1 // Январь — переход через год.
                ? Self.month(year: today.year - 1, month: 12) // Декабрь прошлого года.
                : Self.month(year: today.year, month: today.month - 1) // Предыдущий месяц того же года.
        case .last30Days, .last90Days: // Скользящее окно, оканчивающееся сегодня.
            // Первый день окна; у минимальной даты календаря окно обрезается.
            let start = (try? today.adding(days: -(preset.rollingDayCount! - 1))) ?? today
            interval = start...today // Сегодня входит в окно.
        }
        self.interval = interval // Полный период.
        self.elapsed = interval.lowerBound...min(interval.upperBound, max(today, interval.lowerBound)) // Без будущих дней.
    }

    /// Период — календарный месяц.
    var isMonth: Bool { preset.rollingDayCount == nil } // Месяц — без длины окна.

    /// Весь календарный месяц.
    private static func month(year: Int, month: Int) -> ClosedRange<CalendarDate> {
        // Первый день месяца; год 1 у минимальной даты сохраняется.
        let first = (try? CalendarDate(year: max(year, CalendarDate.minYear), month: month, day: 1))!
        // Последний день месяца с учётом високосного года.
        let last = (try? CalendarDate(year: first.year, month: month, day: CalendarDate.daysInMonth(year: first.year, month: month)))!
        return first...last // Месяц целиком.
    }
}
