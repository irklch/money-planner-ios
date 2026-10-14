import SwiftUI

/// Семантические цвета приложения.
///
/// Значения задаются только в `Resources/Assets.xcassets` (папка `Colors` и `AccentColor`),
/// здесь — единственная точка доступа к ним из кода. Экраны не создают `Color` из HEX/RGB.
/// Значения предварительные, до утверждения макета в Figma.
enum AppColor {
    /// Фон экрана.
    static let background = Color(.background)
    /// Фон карточек, строк списка и других поверхностей поверх фона.
    static let surface = Color(.surface)
    /// Основной текст.
    static let textPrimary = Color(.textPrimary)
    /// Вторичный текст: подписи, пояснения.
    static let textSecondary = Color(.textSecondary)
    /// Акцент: основные действия и выделение. Совпадает с глобальным tint приложения.
    static let accent = Color(.accent)
    /// Разделители и тонкие границы.
    static let separator = Color(.separator)
    /// Ошибки и деструктивные состояния.
    static let error = Color(.error)
    /// Успешное состояние.
    static let success = Color(.success)
}

/// Палитра системных и пользовательских категорий.
///
/// Индекс соответствует `colorIndex` категории в контракте бэкенда (0–11, `category_palette_size = 12`).
/// Сопоставление данных конкретной категории с палитрой появится вместе с категориями.
enum CategoryPalette {
    static let colors: [Color] = [
        Color(.category00), Color(.category01), Color(.category02), Color(.category03),
        Color(.category04), Color(.category05), Color(.category06), Color(.category07),
        Color(.category08), Color(.category09), Color(.category10), Color(.category11),
    ]

    /// Цвет по индексу палитры. Индекс вне диапазона сворачивается по модулю,
    /// чтобы неизвестное значение с сервера не приводило к падению.
    static func color(at index: Int) -> Color {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }
}
