// Money.swift
// Денежная сумма в целых копейках и точное преобразование decimal-строк контракта API.
// Float и Double не используются ни для хранения, ни для вычислений.

// Foundation нужен для протокола LocalizedError-совместимых типов и строковых операций.
import Foundation

/// Денежная сумма в рублях, хранимая как целое число копеек.
///
/// Контракт API (`contract/openapi.yaml → Money`) передаёт суммы decimal-строкой ровно
/// с двумя знаками после точки: `"250.50"`. Валюта в MVP одна — RUB, поэтому в значении
/// она не хранится. Арифметика проверяет переполнение и никогда не округляет.
nonisolated struct Money: Sendable, Hashable, Comparable {
    /// Код валюты всех сумм MVP (контракт: «суммы — decimal-строки с 2 знаками (RUB)»).
    static let currencyCode = "RUB"
    /// Число копеек в рубле.
    static let minorUnitsPerUnit: Int64 = 100
    /// Число знаков после точки в decimal-строке контракта.
    static let fractionDigits = 2
    /// Нулевая сумма (для накопления итогов).
    static let zero = Money(minorUnits: 0)

    /// Сумма в копейках.
    let minorUnits: Int64

    /// Создаёт сумму из числа копеек. Проверка допустимого диапазона расхода — `ExpenseRules`.
    init(minorUnits: Int64) {
        self.minorUnits = minorUnits // Значение хранится как есть.
    }

    /// Разбирает decimal-строку контракта: `^(0|[1-9]\d*)\.\d{2}$`.
    ///
    /// Строка с другим числом знаков после точки, знаком, экспонентой, пробелами, запятой
    /// или ведущими нулями отклоняется: лишние знаки не округляются молча.
    /// - Throws: `MoneyError.invalidFormat`, `.tooManyFractionDigits` или `.overflow`.
    init(apiString: String) throws(MoneyError) {
        // Части строки до и после точки.
        let parts = apiString.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw .invalidFormat } // Ровно одна точка.
        // Целая часть суммы.
        let integerPart = parts[0]
        // Дробная часть суммы.
        let fractionPart = parts[1]
        guard Self.isASCIIDigits(integerPart), Self.isASCIIDigits(fractionPart) else { throw .invalidFormat } // Только цифры 0–9.
        guard integerPart.count == 1 || integerPart.first != "0" else { throw .invalidFormat } // Без ведущих нулей.
        guard fractionPart.count <= Self.fractionDigits else { throw .tooManyFractionDigits } // Лишние знаки не округляем.
        guard fractionPart.count == Self.fractionDigits else { throw .invalidFormat } // Контракт требует ровно 2 знака.

        // Рубли; переполнение проверяется на каждой цифре.
        var units: Int64 = 0
        for digit in integerPart { // Цифры целой части слева направо.
            units = try Self.checkedAppend(digit: digit, to: units) // units = units * 10 + digit.
        }
        // Копейки из двух цифр дробной части (0…99), переполниться не могут.
        let cents = Int64(fractionPart)! // Строка из двух ASCII-цифр всегда преобразуется.
        // Рубли в копейках.
        let (scaled, multiplyOverflow) = units.multipliedReportingOverflow(by: Self.minorUnitsPerUnit)
        guard !multiplyOverflow else { throw .overflow } // Сумма не помещается в Int64 копеек.
        // Итог в копейках.
        let (total, addOverflow) = scaled.addingReportingOverflow(cents)
        guard !addOverflow else { throw .overflow } // Сумма не помещается в Int64 копеек.
        self.minorUnits = total // Точное значение без округления.
    }

    /// Decimal-строка контракта: `"250.50"`. Для отрицательных сумм — с ведущим минусом.
    var apiString: String {
        // Абсолютное значение копеек; `magnitude` корректен и для `Int64.min`.
        let magnitude = minorUnits.magnitude
        // Рубли.
        let units = magnitude / UInt64(Self.minorUnitsPerUnit)
        // Копейки.
        let cents = magnitude % UInt64(Self.minorUnitsPerUnit)
        // Знак суммы.
        let sign = minorUnits < 0 ? "-" : ""
        return "\(sign)\(units).\(cents < 10 ? "0" : "")\(cents)" // Ровно две цифры после точки.
    }

    /// Сумма двух значений.
    /// - Throws: `MoneyError.overflow`, если результат не помещается в Int64 копеек.
    func adding(_ other: Money) throws(MoneyError) -> Money {
        // Результат и признак переполнения.
        let (result, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw .overflow } // Не допускаем молчаливого переполнения.
        return Money(minorUnits: result) // Точная сумма.
    }

    /// Сравнение сумм по числу копеек.
    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.minorUnits < rhs.minorUnits // Порядок совпадает с порядком копеек.
    }

    /// Проверяет, что подстрока не пуста и состоит только из ASCII-цифр.
    private static func isASCIIDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber } // `isNumber` без `isASCII` пропустил бы «٣».
    }

    /// Добавляет цифру справа: `value * 10 + digit` с проверкой переполнения.
    private static func checkedAppend(digit: Character, to value: Int64) throws(MoneyError) -> Int64 {
        // Значение цифры 0–9.
        let digitValue = Int64(digit.asciiValue! - Character("0").asciiValue!) // Цифра уже проверена как ASCII.
        // Сдвиг на разряд.
        let (shifted, multiplyOverflow) = value.multipliedReportingOverflow(by: 10)
        guard !multiplyOverflow else { throw .overflow } // Слишком много разрядов.
        // Новое значение.
        let (result, addOverflow) = shifted.addingReportingOverflow(digitValue)
        guard !addOverflow else { throw .overflow } // Слишком большое значение.
        return result // Значение с добавленной цифрой.
    }
}

/// Ошибка разбора или вычисления денежной суммы.
nonisolated enum MoneyError: Error, Sendable, Equatable {
    /// Строка не соответствует формату `0.00` контракта (знак, экспонента, пробелы, запятая, ведущие нули, нет точки).
    case invalidFormat
    /// Больше двух знаков после точки: значение не округляется.
    case tooManyFractionDigits
    /// Значение не помещается в Int64 копеек.
    case overflow
}
