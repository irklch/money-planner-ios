// AppTypography.swift
// Семантические роли текста: шрифт и цвет по умолчанию для каждой роли.

// SwiftUI нужен для Font, Color и модификатора View.
import SwiftUI

/// Семантические роли текста.
///
/// Каждая роль опирается на системный text style, поэтому масштабируется Dynamic Type.
/// Экраны выбирают роль через `.textStyle(_:)`, а не задают шрифт напрямую.
/// Значения предварительные, до утверждения макета в Figma.
enum AppTextStyle: CaseIterable {
    /// Крупный заголовок экрана вне навигационной панели.
    case screenTitle
    /// Заголовок секции или карточки.
    case sectionTitle
    /// Основной текст.
    case body
    /// Подпись, вторичная информация.
    case caption
    /// Денежная сумма: цифры одинаковой ширины, чтобы суммы не «прыгали».
    case amount
    /// Текст кнопки.
    case button

    /// Шрифт роли: системный text style, начертание и дизайн.
    var font: Font {
        switch self { // Выбираем шрифт по роли.
        case .screenTitle: .system(.largeTitle, design: .default, weight: .bold) // Крупный жирный заголовок.
        case .sectionTitle: .system(.title3, design: .default, weight: .semibold) // Полужирный заголовок секции.
        case .body: .system(.body, design: .default, weight: .regular) // Обычный основной текст.
        case .caption: .system(.footnote, design: .default, weight: .regular) // Мелкий текст подписи.
        case .amount: .system(.title2, design: .rounded, weight: .semibold).monospacedDigit() // Скруглённые цифры одинаковой ширины для сумм.
        case .button: .system(.body, design: .default, weight: .semibold) // Полужирный текст кнопки.
        }
    }

    /// Цвет по умолчанию для роли.
    var color: Color {
        switch self { // Выбираем цвет по роли.
        case .caption: AppColor.textSecondary // Подписи — вторичным цветом.
        case .screenTitle, .sectionTitle, .body, .amount: AppColor.textPrimary // Основной текст и заголовки — основным цветом.
        case .button: AppColor.accent // Кнопки — акцентным цветом.
        }
    }
}

/// Применение ролей текста к любому View.
extension View {
    /// Применяет шрифт и цвет семантической роли текста.
    func textStyle(_ style: AppTextStyle) -> some View {
        font(style.font).foregroundStyle(style.color) // Задаём шрифт роли и её цвет по умолчанию.
    }
}
