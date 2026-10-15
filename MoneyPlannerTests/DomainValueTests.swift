// DomainValueTests.swift
// Тесты независимых типов: деньги, календарная дата, правила текста, UUIDv5 и реестр системных категорий.

import Foundation // Foundation нужен для Date, TimeZone и ISO8601DateFormatter.
import Testing // Testing нужен для @Suite, @Test и #expect.
@testable import MoneyPlanner // Доступ к внутренним типам приложения.

// MARK: - Деньги

@Suite("Money") // Набор тестов денег.
struct MoneyTests { // Тесты Money.
    /// Decimal-строки контракта разбираются точно, без потери копеек.
    @Test(arguments: [
        ("0.01", Int64(1)), // Минимальная сумма.
        ("250.50", 25_050), // Рубли и копейки.
        ("0.10", 10), // Ноль в копейках сохраняется.
        ("1.00", 100), // Целые рубли.
        ("999999999.99", 99_999_999_999), // Максимум контракта.
    ])
    func parsesContractStrings(text: String, minorUnits: Int64) throws { // Параметризованный тест.
        let money = try Money(apiString: text) // Разобранная сумма.
        #expect(money.minorUnits == minorUnits) // Точное число копеек.
        #expect(money.apiString == text) // Обратное преобразование без потерь.
    }

    /// Строки вне формата `0.00` отклоняются.
    @Test(arguments: [
        "", "250", "250.5", ".50", "250.", "-1.00", "+1.00", "1e2", "1E2.00", " 1.00", "1.00 ", // Пусто, нет копеек, нет целой части, знак, экспонента, пробелы.
        "1,00", "01.00", "00.50", "1.0.0", "1 000.00", "١.٠٠", "NaN", "inf", // Запятая, ведущие нули, лишняя точка, разделитель, не-ASCII, спецзначения.
    ])
    func rejectsInvalidFormat(text: String) { // Параметризованный тест.
        #expect(throws: MoneyError.invalidFormat) { try Money(apiString: text) } // Формат отклонён.
    }

    /// Лишние знаки после точки не округляются, а отклоняются.
    @Test(arguments: ["1.005", "250.500", "0.001"])
    func rejectsExtraFractionDigits(text: String) { // Параметризованный тест.
        #expect(throws: MoneyError.tooManyFractionDigits) { try Money(apiString: text) } // Не округляется.
    }

    /// Значение, не помещающееся в Int64 копеек, — ошибка переполнения, а не обрезка.
    @Test(arguments: ["92233720368547758.08", "99999999999999999999.00", "92233720368547759.00"])
    func rejectsOverflow(text: String) { // Параметризованный тест.
        #expect(throws: MoneyError.overflow) { try Money(apiString: text) } // Переполнение Int64.
    }

    /// Наибольшее представимое значение разбирается без переполнения.
    @Test func parsesInt64Boundary() throws {
        #expect(try Money(apiString: "92233720368547758.07").minorUnits == .max) // Int64.max копеек — ещё допустимо.
    }

    /// Сложение проверяет переполнение.
    @Test func additionChecksOverflow() throws {
        #expect(try Money.api("0.10").adding(.api("0.20")) == .api("0.30")) // Точная сумма без Double.
        #expect(throws: MoneyError.overflow) { try Money(minorUnits: .max).adding(Money(minorUnits: 1)) } // Переполнение при сложении.
    }

    /// Отрицательные значения и ноль форматируются корректно.
    @Test func formatsSignAndZero() {
        #expect(Money.zero.apiString == "0.00") // Ноль.
        #expect(Money(minorUnits: -5).apiString == "-0.05") // Отрицательная сумма с ведущим нулём.
        #expect(Money(minorUnits: .min).apiString == "-92233720368547758.08") // Int64.min без переполнения magnitude.
    }

    /// Диапазон суммы расхода: 0.01 … 999 999 999.99.
    @Test func expenseAmountRange() throws {
        #expect(try ExpenseAmountRule.validated(.api("0.01")) == .api("0.01")) // Минимум.
        #expect(try ExpenseAmountRule.validated(.api("999999999.99")) == .api("999999999.99")) // Максимум.
        #expect(throws: LedgerError.invalidAmount) { try ExpenseAmountRule.validated(.api("0.00")) } // Ноль запрещён.
        #expect(throws: LedgerError.invalidAmount) { try ExpenseAmountRule.validated(.api("1000000000.00")) } // Больше максимума.
        #expect(throws: LedgerError.invalidAmount) { try ExpenseAmountRule.validated(Money(minorUnits: -1)) } // Отрицательная.
    }
}

// MARK: - Календарная дата

@Suite("CalendarDate") // Набор тестов дат.
struct CalendarDateTests { // Тесты CalendarDate.
    /// Високосные годы по григорианскому правилу.
    @Test func leapYears() throws {
        #expect(try CalendarDate(isoString: "2024-02-29").day == 29) // Високосный 2024.
        #expect(try CalendarDate(isoString: "2000-02-29").day == 29) // 2000 делится на 400 — високосный.
        #expect(throws: CalendarDateError.invalidDate) { try CalendarDate(isoString: "2025-02-29") } // 2025 — не високосный.
        #expect(throws: CalendarDateError.invalidDate) { try CalendarDate(isoString: "1900-02-29") } // 1900 делится на 100 — не високосный.
        #expect(throws: CalendarDateError.invalidDate) { try CalendarDate(isoString: "2100-02-29") } // 2100 — не високосный.
    }

    /// Несуществующие дни отклоняются.
    @Test(arguments: ["2026-04-31", "2026-13-01", "2026-00-10", "2026-01-00", "2026-06-31", "0000-01-01"])
    func rejectsNonexistentDays(text: String) { // Параметризованный тест.
        #expect(throws: CalendarDateError.invalidDate) { try CalendarDate(isoString: text) } // Дня не существует.
    }

    /// Строки вне формата `YYYY-MM-DD` отклоняются.
    @Test(arguments: ["2026-1-01", "26-01-01", "2026/01/01", "2026-01-01T00:00:00Z", " 2026-01-01", "２０２６-01-01", ""])
    func rejectsInvalidFormat(text: String) { // Параметризованный тест.
        #expect(throws: CalendarDateError.invalidFormat) { try CalendarDate(isoString: text) } // Формат отклонён.
    }

    /// Строка, ключ хранения и номер дня взаимно обратимы.
    @Test(arguments: ["1970-01-01", "1999-12-31", "2024-02-29", "2026-10-14", "0001-01-01", "9999-12-31"])
    func roundTrips(text: String) throws { // Параметризованный тест.
        let date = try CalendarDate(isoString: text) // Разобранная дата.
        #expect(date.isoString == text) // Строка контракта.
        #expect(try CalendarDate(storageKey: date.storageKey) == date) // Ключ хранения.
        #expect(try date.adding(days: 0) == date) // Арифметика по номеру дня.
    }

    /// Арифметика дней учитывает 29 февраля.
    @Test func addsDaysAcrossLeapDay() throws {
        #expect(try CalendarDate.iso("2024-02-28").adding(days: 1) == .iso("2024-02-29")) // 28 → 29 февраля високосного года.
        #expect(try CalendarDate.iso("2024-02-29").adding(days: 1) == .iso("2024-03-01")) // 29 февраля → 1 марта.
        #expect(try CalendarDate.iso("2025-02-28").adding(days: 1) == .iso("2025-03-01")) // 28 февраля → 1 марта невисокосного года.
        #expect(try CalendarDate.iso("2026-01-01").adding(days: -1) == .iso("2025-12-31")) // Через границу года назад.
        #expect(CalendarDate.iso("1970-01-01").daysSinceEpoch == 0) // Эпоха — день 0.
        #expect(throws: CalendarDateError.invalidDate) { try CalendarDate.iso("9999-12-31").adding(days: 1) } // Выход за 9999 год.
    }

    /// Порядок дат совпадает с хронологическим.
    @Test func ordering() {
        #expect(CalendarDate.iso("2025-12-31") < .iso("2026-01-01")) // Через границу года.
        #expect(CalendarDate.iso("2026-02-28") < .iso("2026-03-01")) // Через границу месяца.
    }

    /// «Сегодня» зависит от пояса, а сохранённая дата — нет.
    @Test func todayDependsOnTimeZoneButValueDoesNot() throws {
        // 2026-10-13 22:30 UTC: в Москве уже 14 октября, в Лос-Анджелесе ещё 13-е.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-13T22:30:00Z"))
        let moscow = try #require(TimeZone(identifier: "Europe/Moscow")) // Пояс UTC+3.
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles")) // Пояс UTC−7 (летнее время).
        #expect(CalendarDate.today(in: moscow, now: instant) == .iso("2026-10-14")) // В Москве уже 14-е.
        #expect(CalendarDate.today(in: losAngeles, now: instant) == .iso("2026-10-13")) // В Лос-Анджелесе ещё 13-е.
        #expect(CalendarDate.today(in: .gmt, now: instant) == .iso("2026-10-13")) // В UTC 13-е.

    }
}

// MARK: - Правила текста

@Suite("Text rules") // Набор тестов правил текста.
struct TextRulesTests { // Тесты правил текста.
    /// Вектор правила комментария из контракта.
    struct CommentVector: Decodable {
        let id: String // Идентификатор вектора.
        let input: String // Исходная строка.
        let normalized: String? // Ожидаемая нормализация.
        let scalarCount: Int // Ожидаемая длина.
        let syncValid: Bool // Допустимо ли для sync.
        let importTruncated: String? // Ожидаемая обрезка импорта.
    }

    /// Файл векторов комментария.
    struct CommentVectors: Decodable {
        let maxScalars: Int // Лимит из контракта.
        let cases: [CommentVector] // Векторы.
    }

    /// Строки сравниваются по скалярам: Swift считает канонически эквивалентные строки равными.
    private func sameScalars(_ lhs: String?, _ rhs: String?) -> Bool {
        lhs.map { Array($0.unicodeScalars) } == rhs.map { Array($0.unicodeScalars) } // Сравнение массивов скаляров.
    }

    /// Реализация совпадает с эталоном контракта на всех векторах.
    @Test func commentRuleMatchesContractVectors() throws {
        let vectors = try ContractFixtures.load(CommentVectors.self, named: "comment-vectors") // Векторы из fixtures.
        #expect(vectors.maxScalars == ExpenseCommentRule.maxScalars) // Лимит совпадает.
        #expect(vectors.cases.count >= 37) // Все 37 векторов на месте.
        for vector in vectors.cases { // Каждый вектор.
            let normalized = ExpenseCommentRule.normalize(vector.input) // Нормализация.
            #expect(sameScalars(normalized, vector.normalized), "normalized: \(vector.id)") // Совпадает с эталоном.
            #expect(ExpenseCommentRule.scalarCount(of: normalized) == vector.scalarCount, "scalarCount: \(vector.id)") // Длина совпадает.
            #expect(sameScalars(ExpenseCommentRule.truncated(normalized), vector.importTruncated), "truncated: \(vector.id)") // Обрезка по графемам совпадает.
            if vector.syncValid { // Допустимый комментарий.
                #expect(sameScalars(try ExpenseCommentRule.validated(vector.input), vector.normalized), "valid: \(vector.id)") // Принят и нормализован.
            } else {
                #expect(throws: LedgerError.commentTooLong, "invalid: \(vector.id)") { // Слишком длинный — ошибка, без обрезки.
                    try ExpenseCommentRule.validated(vector.input) // Проверка ручного ввода.
                }
            }
        }
    }

    /// Кириллица: 200 символов допустимы, 201 — нет; длинный текст не обрезается молча.
    @Test func cyrillicLimit() throws {
        #expect(try ExpenseCommentRule.validated(String(repeating: "ж", count: 200))?.count == 200) // 200 кириллических символов допустимы.
        #expect(throws: LedgerError.commentTooLong) { try ExpenseCommentRule.validated(String(repeating: "ж", count: 201)) } // 201 — нет.
        // «й» из двух кодовых точек после NFC — одна: 200 таких символов допустимы.
        let decomposed = String(repeating: "\u{0438}\u{0306}", count: 200)
        #expect(try ExpenseCommentRule.validated(decomposed)?.unicodeScalars.count == 200) // После NFC 200 scalar values.
    }

    /// Составные эмодзи считаются по кодовым точкам: 👨‍👩‍👧 = 5, 👍🏽 = 2, 🇷🇺 = 2.
    @Test func compositeEmojiCount() throws {
        #expect(ExpenseCommentRule.scalarCount(of: "👨‍👩‍👧") == 5) // Семья с ZWJ — 5.
        #expect(ExpenseCommentRule.scalarCount(of: "👍🏽") == 2) // Тон кожи — 2.
        #expect(ExpenseCommentRule.scalarCount(of: "🇷🇺") == 2) // Флаг — 2.
        let fits = String(repeating: "a", count: 195) + "👨‍👩‍👧" // 195 + 5 = 200.
        #expect(try ExpenseCommentRule.validated(fits) == fits) // Допустимо.
        let over = String(repeating: "a", count: 196) + "👨‍👩‍👧" // 196 + 5 = 201.
        #expect(throws: LedgerError.commentTooLong) { try ExpenseCommentRule.validated(over) } // Недопустимо.
        // Обрезка для импорта не разрезает графему.
        #expect(ExpenseCommentRule.truncated(over) == String(repeating: "a", count: 196))
    }

    /// Пустой комментарий хранится как nil.
    @Test func emptyCommentIsNil() throws {
        #expect(try ExpenseCommentRule.validated(nil) == nil) // nil — без комментария.
        #expect(try ExpenseCommentRule.validated(" \n\t ") == nil) // Только пробелы и Cc — пусто.
    }

    /// Название категории: 1–24 scalar values после нормализации, хранится как введено.
    @Test func categoryName() throws {
        #expect(try CategoryRules.validatedName("  Кофе с собой ") == "Кофе с собой") // Пробелы по краям обрезаны, внутри сохранены.
        #expect(try CategoryRules.validatedName("Кафе ☕️") == "Кафе ☕️") // Эмодзи в названии допустимы.
        #expect(try CategoryRules.validatedName(String(repeating: "я", count: 24)).count == 24) // 24 символа — максимум.
        #expect(throws: LedgerError.invalidCategoryName) { try CategoryRules.validatedName(String(repeating: "я", count: 25)) } // 25 — больше.
        #expect(throws: LedgerError.invalidCategoryName) { try CategoryRules.validatedName("   ") } // Только пробелы.
        #expect(throws: LedgerError.invalidCategoryName) { try CategoryRules.validatedName("") } // Пусто.
    }

    /// Эмодзи категории — ровно одна графема.
    @Test func categoryEmoji() throws {
        #expect(try CategoryRules.validatedEmoji("🛒") == "🛒") // Простой эмодзи.
        #expect(try CategoryRules.validatedEmoji("👨‍👩‍👧") == "👨‍👩‍👧") // ZWJ-последовательность — одна графема.
        #expect(try CategoryRules.validatedEmoji("🇷🇺") == "🇷🇺") // Флаг — одна графема.
        #expect(throws: LedgerError.invalidEmoji) { try CategoryRules.validatedEmoji("") } // Пусто.
        #expect(throws: LedgerError.invalidEmoji) { try CategoryRules.validatedEmoji("🛒🛒") } // Две графемы.
        #expect(throws: LedgerError.invalidEmoji) { try CategoryRules.validatedEmoji(" ") } // Пробел.
        #expect(throws: LedgerError.invalidEmoji) { try CategoryRules.validatedEmoji("\n") } // Управляющий символ.
    }

    /// Индекс цвета — 0–11, как палитра `CategoryPalette`.
    @MainActor
    @Test func colorIndex() throws { // Тест индекса цвета.
        #expect(CategoryRules.colorIndexRange.count == CategoryPalette.colors.count) // Диапазон совпадает с палитрой.
        #expect(try CategoryRules.validatedColorIndex(0) == 0) // Минимум.
        #expect(try CategoryRules.validatedColorIndex(11) == 11) // Максимум.
        #expect(throws: LedgerError.invalidColorIndex) { try CategoryRules.validatedColorIndex(12) } // Больше максимума.
        #expect(throws: LedgerError.invalidColorIndex) { try CategoryRules.validatedColorIndex(-1) } // Отрицательный.
    }
}

// MARK: - Идентификаторы и реестр

@Suite("Contract identifiers") // Набор тестов идентификаторов контракта.
struct ContractIdentifierTests { // Тесты реестра и UUIDv5.
    /// Вектор UUIDv5 отметки дня.
    struct DayMarkVector: Decodable {
        let date: String // Дата.
        let entityId: String // Ожидаемый UUID.
    }

    /// Файл векторов отметки дня.
    struct DayMarkVectors: Decodable {
        let namespace: String // Пространство имён.
        let cases: [DayMarkVector] // Векторы.
    }

    /// Запись реестра системных категорий.
    struct RegistryCategory: Decodable {
        let key: String // Ключ.
        let id: String // UUID.
        let nameRu: String // Русское название.
        let emoji: String // Эмодзи.
        let colorIndex: Int // Цвет.
        let sortOrder: Int // Порядок.
        let archivable: Bool // Архивируемость.
    }

    /// Реестр системных категорий.
    struct Registry: Decodable {
        let status: String // Статус утверждения.
        let fallbackCategoryId: String // UUID «Другое».
        let categories: [RegistryCategory] // Категории.
    }

    /// `entityId` отметки дня совпадает с векторами контракта.
    @Test func dayMarkIDMatchesVectors() throws {
        let vectors = try ContractFixtures.load(DayMarkVectors.self, named: "day-mark-id-vectors") // Векторы из fixtures.
        #expect(DayMarkID.namespace.contractString == vectors.namespace) // Пространство имён совпадает.
        for vector in vectors.cases { // Каждый вектор.
            #expect(DayMarkID.make(for: .iso(vector.date)).contractString == vector.entityId, "\(vector.date)") // UUIDv5 совпадает.
        }
    }

    /// Каталог приложения совпадает с утверждённым реестром контракта.
    @MainActor
    @Test func systemCategoriesMatchRegistry() throws { // Тест реестра.
        let registry = try ContractFixtures.load(Registry.self, named: "system-categories") // Реестр из fixtures.
        #expect(registry.status == "approved") // Реестр утверждён.
        #expect(SystemCategory.fallback.idString == registry.fallbackCategoryId) // Резервная категория.
        #expect(SystemCategory.allCases.map(\.rawValue) == registry.categories.map(\.key)) // Тот же набор и порядок.
        for entry in registry.categories { // Каждая запись.
            let category = try #require(SystemCategory(rawValue: entry.key)) // Категория приложения по ключу.
            #expect(category.idString == entry.id) // UUID строкой.
            #expect(category.id.contractString == entry.id) // UUID в нижнем регистре.
            #expect(category.emoji == entry.emoji) // Эмодзи.
            #expect(category.colorIndex == entry.colorIndex) // Цвет.
            #expect(category.sortOrder == entry.sortOrder) // Порядок.
            #expect(category.isArchivable == entry.archivable) // Архивируемость.
            #expect(String(localized: category.name) == entry.nameRu, "\(entry.key)") // Название из String Catalog.
        }
    }
}
