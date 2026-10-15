// TextRules.swift
// Правила пользовательского текста из контракта: комментарий расхода (план §3.3),
// название и эмодзи пользовательской категории (план §3.2, api-contract §6).

// Foundation нужен для NFC-нормализации (`precomposedStringWithCanonicalMapping`).
import Foundation

/// Правило комментария расхода (план §3.3, `contract/vectors/comment.json`).
///
/// Повторяет эталон `contract/swift/comment_rule_check.swift`: символы классифицируются через
/// `Unicode.Scalar.Properties.generalCategory`, а не через `CharacterSet` — тот обрезал бы U+200B.
nonisolated enum ExpenseCommentRule {
    /// Максимальная длина в Unicode scalar values (`EXPENSE_COMMENT_MAX_SCALARS`).
    static let maxScalars = 200

    /// NFC → удалить символы категории Cc → обрезать по краям Zs/Zl/Zp → пустая строка = `nil`.
    static func normalize(_ text: String) -> String? {
        // Строка в форме NFC: длина считается после композиции.
        let nfc = text.precomposedStringWithCanonicalMapping
        // Скаляры без управляющих символов (Cc), в том числе внутренних.
        var scalars = nfc.unicodeScalars.filter { $0.properties.generalCategory != .control }
        while let first = scalars.first, isSeparator(first) { scalars.removeFirst() } // Пробельные символы слева.
        while let last = scalars.last, isSeparator(last) { scalars.removeLast() } // Пробельные символы справа.
        // Результат как строка.
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars) // Собираем строку из оставшихся скаляров.
        return view.isEmpty ? nil : String(view) // Пустой комментарий хранится как nil.
    }

    /// Длина нормализованного комментария в Unicode scalar values.
    static func scalarCount(of normalized: String?) -> Int {
        normalized?.unicodeScalars.count ?? 0 // nil — пустой комментарий.
    }

    /// Нормализует комментарий ручного ввода и проверяет длину. Длинный текст не обрезается.
    /// - Throws: `LedgerError.commentTooLong`, если после нормализации больше 200 scalar values.
    static func validated(_ text: String?) throws(LedgerError) -> String? {
        guard let text else { return nil } // Комментарий необязателен.
        // Нормализованный комментарий.
        let normalized = normalize(text)
        guard scalarCount(of: normalized) <= maxScalars else { throw .commentTooLong } // Sync не обрезает, а отклоняет.
        return normalized // Значение для хранения.
    }

    /// Наибольший префикс из целых графем длиной ≤ `limit` scalar values (для импорта и вставки).
    static func truncated(_ normalized: String?, limit: Int = maxScalars) -> String? {
        guard let normalized else { return nil } // Нечего обрезать.
        // Скаляры принятого префикса.
        var output = String.UnicodeScalarView()
        for character in normalized { // Идём по графемам (Character), чтобы не разрезать их.
            if output.count + character.unicodeScalars.count > limit { break } // Графема не режется.
            output.append(contentsOf: character.unicodeScalars) // Графема помещается целиком.
        }
        return output.isEmpty ? nil : String(output) // Пустой префикс — nil.
    }

    /// Пробельный символ общих категорий Zs/Zl/Zp.
    static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory { // Категория Unicode.
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: true // Обрезаются по краям.
        default: false // Cf (U+200B, U+FEFF) и прочие сохраняются.
        }
    }
}

/// Правила полей пользовательской категории (`UserCategoryPayload` контракта).
nonisolated enum CategoryRules {
    /// Максимальная длина названия в Unicode scalar values (`CATEGORY_NAME_MAX_SCALARS`).
    static let nameMaxScalars = 24
    /// Максимальная длина эмодзи в кодовых точках (`maxLength: 16` схемы контракта).
    static let emojiMaxScalars = 16
    /// Допустимые индексы цвета (`CATEGORY_COLOR_INDEX_MAX` = 11, палитра из 12 цветов).
    static let colorIndexRange = 0...11

    /// Нормализует и проверяет название: NFC, без Cc, без пробельных символов по краям, 1–24 scalar values.
    ///
    /// Контракт задаёт только длину; нормализация — та же, что у комментария, чтобы длина
    /// на устройстве и на сервере считалась одинаково. Название хранится как ввёл пользователь.
    /// - Throws: `LedgerError.invalidCategoryName`.
    static func validatedName(_ name: String) throws(LedgerError) -> String {
        guard let normalized = ExpenseCommentRule.normalize(name), // Название после нормализации не пустое…
              normalized.unicodeScalars.count <= nameMaxScalars else { throw .invalidCategoryName } // 1–24 scalar values.
        return normalized // Название для хранения.
    }

    /// Проверяет эмодзи: ровно одна графема, ≤ 16 кодовых точек, без пробелов и управляющих символов.
    /// - Throws: `LedgerError.invalidEmoji`.
    static func validatedEmoji(_ emoji: String) throws(LedgerError) -> String {
        // Эмодзи в NFC.
        let nfc = emoji.precomposedStringWithCanonicalMapping
        guard nfc.count == 1, nfc.unicodeScalars.count <= emojiMaxScalars else { throw .invalidEmoji } // Одна графема.
        guard nfc.unicodeScalars.allSatisfy({ // Нет пробельных и управляющих символов.
            !ExpenseCommentRule.isSeparator($0) && $0.properties.generalCategory != .control // Не Zs/Zl/Zp и не Cc.
        }) else { throw .invalidEmoji } // Иначе эмодзи некорректен.
        return nfc // Эмодзи для хранения.
    }

    /// Проверяет индекс цвета палитры `CategoryPalette`.
    /// - Throws: `LedgerError.invalidColorIndex`.
    static func validatedColorIndex(_ index: Int) throws(LedgerError) -> Int {
        guard colorIndexRange.contains(index) else { throw .invalidColorIndex } // 0–11.
        return index // Индекс для хранения.
    }
}

/// Правила суммы расхода (`Money` контракта: `0.01` … `999999999.99`).
nonisolated enum ExpenseAmountRule {
    /// Допустимый диапазон суммы расхода в копейках.
    static let range: ClosedRange<Int64> = 1...99_999_999_999

    /// Проверяет, что сумма расхода больше нуля и не больше 999 999 999.99 ₽.
    /// - Throws: `LedgerError.invalidAmount`.
    static func validated(_ amount: Money) throws(LedgerError) -> Money {
        guard range.contains(amount.minorUnits) else { throw .invalidAmount } // Вне диапазона контракта.
        return amount // Сумма для хранения.
    }
}
