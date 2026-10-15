// CalendarDate.swift
// Календарный день расхода `YYYY-MM-DD` без времени и часового пояса.

// Foundation нужен для Date, Calendar и TimeZone при вычислении «сегодня».
import Foundation

/// Календарный день по григорианскому календарю, например `2026-10-14`.
///
/// Это не момент времени: значение не зависит от часового пояса, поэтому смена пояса
/// не переносит расход на соседний день. Часовой пояс нужен только один раз —
/// чтобы определить, какой день сейчас (`today(in:now:)`). Моменты `createdAt`/`updatedAt`
/// хранятся отдельно как `Date`.
nonisolated struct CalendarDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Минимальный допустимый год (формат `YYYY` — четыре цифры).
    static let minYear = 1
    /// Максимальный допустимый год.
    static let maxYear = 9999

    /// Год (1–9999).
    let year: Int
    /// Месяц (1–12).
    let month: Int
    /// День месяца (1–28…31 в зависимости от месяца и года).
    let day: Int

    /// Создаёт дату, проверяя, что такой день существует (включая 29 февраля високосного года).
    /// - Throws: `CalendarDateError.invalidDate`.
    init(year: Int, month: Int, day: Int) throws(CalendarDateError) {
        guard (Self.minYear...Self.maxYear).contains(year), (1...12).contains(month) else { throw .invalidDate } // Год и месяц в диапазоне.
        guard (1...Self.daysInMonth(year: year, month: month)).contains(day) else { throw .invalidDate } // День существует в этом месяце.
        self.year = year // Год.
        self.month = month // Месяц.
        self.day = day // День.
    }

    /// Разбирает строку контракта `YYYY-MM-DD` (ровно 10 ASCII-символов).
    /// - Throws: `CalendarDateError.invalidFormat` или `.invalidDate`.
    init(isoString: String) throws(CalendarDateError) {
        // Символы строки как UTF-8 байты: формат строго ASCII.
        let bytes = Array(isoString.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { throw .invalidFormat } // Шаблон YYYY-MM-DD.
        // Позиции цифр в шаблоне.
        let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9]
        guard digitPositions.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[$0]) }) else { throw .invalidFormat } // Только цифры.
        // Число из диапазона байтов.
        func number(_ range: Range<Int>) -> Int {
            range.reduce(0) { $0 * 10 + Int(bytes[$1] - UInt8(ascii: "0")) } // Десятичное значение цифр.
        }
        try self.init(year: number(0..<4), month: number(5..<7), day: number(8..<10)) // Проверка существования дня.
    }

    /// Создаёт дату из ключа хранения `YYYYMMDD`.
    /// - Throws: `CalendarDateError.invalidDate` для некорректного ключа.
    init(storageKey: Int) throws(CalendarDateError) {
        try self.init(year: storageKey / 10_000, month: storageKey / 100 % 100, day: storageKey % 100) // Разбор разрядов ключа.
    }

    /// Строка контракта `YYYY-MM-DD`.
    var isoString: String {
        // Год с ведущими нулями до 4 цифр.
        let yearText = String(repeating: "0", count: max(0, 4 - String(year).count)) + String(year)
        return "\(yearText)-\(Self.twoDigits(month))-\(Self.twoDigits(day))" // Месяц и день — по две цифры.
    }

    /// Строковое представление для отладки — строка контракта.
    var description: String { isoString } // Совпадает с форматом API.

    /// Ключ хранения `YYYYMMDD`: целое число, порядок которого совпадает с порядком дат.
    var storageKey: Int { year * 10_000 + month * 100 + day } // Например, 20261014.

    /// Номер дня от 1970-01-01 (пролептический григорианский календарь, без часовых поясов).
    var daysSinceEpoch: Int {
        // Алгоритм days_from_civil (H. Hinnant): год начинается с марта, чтобы февраль был последним.
        let shiftedYear = month <= 2 ? year - 1 : year
        // Номер 400-летней эры.
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        // Год внутри эры (0–399).
        let yearOfEra = shiftedYear - era * 400
        // День года, считая от 1 марта (0–365).
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        // День эры (0–146096).
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468 // Сдвиг к 1970-01-01.
    }

    /// Дата, отстоящая на `days` дней (отрицательное значение — назад).
    /// - Throws: `CalendarDateError.invalidDate`, если результат вне 0001–9999.
    func adding(days: Int) throws(CalendarDateError) -> CalendarDate {
        try Self(daysSinceEpoch: daysSinceEpoch + days) // Арифметика по номеру дня, без Calendar.
    }

    /// Текущий календарный день в часовом поясе устройства (или заданном для тестов).
    /// - Parameters:
    ///   - timeZone: часовой пояс, в котором определяется «сегодня».
    ///   - now: текущий момент.
    static func today(in timeZone: TimeZone = .current, now: Date = .now) -> CalendarDate {
        containing(now, in: timeZone) // День, в который попадает текущий момент.
    }

    /// Календарный день, в который попадает момент `instant` в часовом поясе `timeZone`.
    static func containing(_ instant: Date, in timeZone: TimeZone) -> CalendarDate {
        // Григорианский календарь с заданным поясом.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone // День определяется в заданном поясе.
        // Компоненты дня.
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        return try! CalendarDate(year: components.year!, month: components.month!, day: components.day!) // Календарь всегда даёт существующий день.
    }

    /// Порядок дат — хронологический.
    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        lhs.storageKey < rhs.storageKey // Ключ YYYYMMDD упорядочен так же, как даты.
    }

    /// Високосный ли год по григорианскому правилу.
    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 // 2024 и 2000 — да, 1900 и 2100 — нет.
    }

    /// Число дней в месяце.
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month { // Длина месяца.
        case 2: isLeapYear(year) ? 29 : 28 // Февраль зависит от года.
        case 4, 6, 9, 11: 30 // Апрель, июнь, сентябрь, ноябрь.
        default: 31 // Остальные месяцы.
        }
    }

    /// Создаёт дату по номеру дня от 1970-01-01 (алгоритм civil_from_days).
    private init(daysSinceEpoch: Int) throws(CalendarDateError) {
        // Номер дня от 0000-03-01.
        let shifted = daysSinceEpoch + 719_468
        // Номер 400-летней эры.
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        // День эры (0–146096).
        let dayOfEra = shifted - era * 146_097
        // Год внутри эры (0–399).
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        // День года, считая от 1 марта.
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        // Месяц, считая от марта (0–11).
        let marchMonth = (5 * dayOfYear + 2) / 153
        // День месяца.
        let day = dayOfYear - (153 * marchMonth + 2) / 5 + 1
        // Календарный месяц.
        let month = marchMonth < 10 ? marchMonth + 3 : marchMonth - 9
        // Календарный год.
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        try self.init(year: year, month: month, day: day) // Проверка диапазона лет.
    }

    /// Число с ведущим нулём до двух цифр.
    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)" // 7 → "07".
    }
}

/// Ошибка создания календарной даты.
nonisolated enum CalendarDateError: Error, Sendable, Equatable {
    /// Строка не в формате `YYYY-MM-DD`.
    case invalidFormat
    /// Такого дня не существует (31 апреля, 29 февраля невисокосного года, год вне 1–9999).
    case invalidDate
}
