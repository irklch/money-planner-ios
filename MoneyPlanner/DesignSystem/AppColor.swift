// AppColor.swift
// Типизированный доступ к цветам дизайн-системы и палитре категорий.
// Сами значения цветов хранятся только в Resources/Assets.xcassets.

// SwiftUI нужен для типа Color.
import SwiftUI

/// Семантические цвета приложения.
///
/// Значения задаются только в `Resources/Assets.xcassets` (папка `Colors` и `AccentColor`),
/// здесь — единственная точка доступа к ним из кода. Экраны не создают `Color` из HEX/RGB.
/// Значения предварительные, до утверждения макета в Figma.
enum AppColor {
    /// Фон экрана.
    static let background = Color(.background) // Цвет из ассета Colors/Background.
    /// Фон карточек, строк списка и других поверхностей поверх фона.
    static let surface = Color(.surface) // Цвет из ассета Colors/Surface.
    /// Основной текст.
    static let textPrimary = Color(.textPrimary) // Цвет из ассета Colors/TextPrimary.
    /// Вторичный текст: подписи, пояснения.
    static let textSecondary = Color(.textSecondary) // Цвет из ассета Colors/TextSecondary.
    /// Акцент: основные действия и выделение. Совпадает с глобальным tint приложения.
    static let accent = Color(.accent) // Цвет из ассета AccentColor (он же tint приложения).
    /// Разделители и тонкие границы.
    static let separator = Color(.separator) // Цвет из ассета Colors/Separator.
    /// Ошибки и деструктивные состояния.
    static let error = Color(.error) // Цвет из ассета Colors/Error.
    /// Успешное состояние.
    static let success = Color(.success) // Цвет из ассета Colors/Success.
}

/// Палитра системных и пользовательских категорий.
///
/// Индекс соответствует `colorIndex` категории в контракте бэкенда (0–11, `category_palette_size = 12`).
/// Сопоставление данных конкретной категории с палитрой появится вместе с категориями.
enum CategoryPalette {
    /// Цвета палитры в порядке индексов 0–11.
    static let colors: [Color] = [
        Color(.category00), Color(.category01), Color(.category02), Color(.category03), // Индексы 0–3.
        Color(.category04), Color(.category05), Color(.category06), Color(.category07), // Индексы 4–7.
        Color(.category08), Color(.category09), Color(.category10), Color(.category11), // Индексы 8–11.
    ]

    /// Цвет по индексу палитры. Индекс вне диапазона сворачивается по модулю,
    /// чтобы неизвестное значение с сервера не приводило к падению.
    static func color(at index: Int) -> Color {
        let count = colors.count // Размер палитры для вычисления остатка.
        return colors[((index % count) + count) % count] // Остаток всегда в 0..<count, в том числе для отрицательных индексов.
    }
}
