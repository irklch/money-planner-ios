// ExpenseFormatting.swift
// Форматирование сумм, дат, периодов и долей для экранов расходов с учётом локали.

// Foundation нужен для Date, Calendar, Locale и FormatStyle.
import Foundation
// SwiftUI нужен для AttributedString-атрибутов цвета.
import SwiftUI

/// Форматирование значений расходов для интерфейса.
///
/// Календарная дата превращается в момент только для форматирования: полдень этого дня в GMT,
/// и форматтер работает в том же GMT. Поэтому день не сдвигается на соседний ни в одном
/// часовом поясе устройства. Язык и порядок частей — из локали.
enum ExpenseFormatting {
    /// Часовой пояс форматирования календарных дат.
    private static let timeZone = TimeZone.gmt

    /// Момент «полдень дня в GMT» для форматтеров.
    static func date(_ day: CalendarDate) -> Date {
        // Григорианский календарь в GMT.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone // Тот же пояс, что у форматтера.
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))! // Существующий день всегда даёт дату.
    }

    /// Сумма: `28 430 ₽`, копейки — только если они есть: `250,50 ₽`.
    static func money(_ amount: Money, locale: Locale = .current) -> String {
        decimal(amount).formatted(currencyStyle(for: amount, locale: locale)) // Валюта RUB в формате локали.
    }

    /// Сумма, у которой знак валюты выделен третичным цветом (итог периода).
    static func heroMoney(_ amount: Money, locale: Locale = .current) -> AttributedString {
        // Сумма с атрибутами частей числа.
        var text = decimal(amount).formatted(currencyStyle(for: amount, locale: locale).attributed)
        for run in text.runs where run.numberSymbol == .currency { // Часть «₽».
            text[run.range].foregroundColor = AppColor.textTertiary // Знак валюты — третичным цветом.
        }
        return text // Готовая строка.
    }

    /// Доля в процентах из десятых долей процента: `23 %`, `1,5 %`.
    static func share(tenths: Int, locale: Locale = .current) -> String {
        // Доля как дробь; floating point — только для отображения уже точно посчитанной доли.
        let fraction = Double(tenths) / 1000
        return fraction.formatted(.percent.precision(.fractionLength(0...1)).locale(locale)) // Один знак после запятой, если он не ноль.
    }

    /// Название месяца с заглавной буквы: «Сентябрь».
    static func monthTitle(_ day: CalendarDate, locale: Locale = .current) -> String {
        monthName(day, locale: locale).capitalized(with: locale) // Первая буква — заглавная.
    }

    /// Название месяца в именительном падеже, строчными: «сентябрь».
    static func monthName(_ day: CalendarDate, locale: Locale = .current) -> String {
        date(day).formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.wide)) // Самостоятельная форма месяца.
    }

    /// Диапазон дат: «1–30 сентября», «3 июля – 30 сентября»; сокращённо — «3 июл. – 30 сент.».
    /// Год добавляется, если диапазон не в текущем году.
    static func range(_ range: ClosedRange<CalendarDate>, abbreviated: Bool = false, today: CalendarDate, locale: Locale = .current) -> String {
        // Стиль интервала в GMT.
        var style = Date.IntervalFormatStyle(locale: locale, timeZone: timeZone)
            .day()
            .month(abbreviated ? .abbreviated : .wide)
        if range.lowerBound.year != today.year || range.upperBound.year != today.year { style = style.year() } // Другой год.
        return (date(range.lowerBound)..<date(range.upperBound)).formatted(style) // Один день — без тире.
    }

    /// День и месяц: «25 сентября»; с годом, если год не текущий.
    static func dayAndMonth(_ day: CalendarDate, today: CalendarDate, locale: Locale = .current) -> String {
        // Стиль даты в GMT.
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(.wide)
        if day.year != today.year { style = style.year() } // Другой год.
        return date(day).formatted(style) // Дата без времени.
    }

    /// Сокращённый день недели внутри фразы: «чт».
    ///
    /// Отдельно стоящий день недели ICU пишет с заглавной («Чт»); в заголовке дня он идёт
    /// после даты, поэтому приводится к строчным по правилам локали.
    static func weekday(_ day: CalendarDate, locale: Locale = .current) -> String {
        date(day).formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated)).lowercased(with: locale) // «чт».
    }

    /// Сумма в рублях как Decimal: копейки / 100 без потери точности.
    private static func decimal(_ amount: Money) -> Decimal {
        Decimal(amount.minorUnits) / Decimal(Money.minorUnitsPerUnit) // Точное деление на 100.
    }

    /// Стиль валюты: без копеек для целых рублей, иначе ровно две цифры.
    private static func currencyStyle(for amount: Money, locale: Locale) -> Decimal.FormatStyle.Currency {
        // Есть ли копейки.
        let hasMinorUnits = amount.minorUnits % Money.minorUnitsPerUnit != 0
        return Decimal.FormatStyle.Currency(code: Money.currencyCode, locale: locale) // Рубли в формате локали.
            .precision(.fractionLength(hasMinorUnits ? Money.fractionDigits : 0)) // 0 или 2 знака.
    }
}
