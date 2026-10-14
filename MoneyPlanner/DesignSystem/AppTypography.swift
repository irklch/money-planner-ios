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

    var font: Font {
        switch self {
        case .screenTitle: .system(.largeTitle, design: .default, weight: .bold)
        case .sectionTitle: .system(.title3, design: .default, weight: .semibold)
        case .body: .system(.body, design: .default, weight: .regular)
        case .caption: .system(.footnote, design: .default, weight: .regular)
        case .amount: .system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
        case .button: .system(.body, design: .default, weight: .semibold)
        }
    }

    /// Цвет по умолчанию для роли.
    var color: Color {
        switch self {
        case .caption: AppColor.textSecondary
        case .screenTitle, .sectionTitle, .body, .amount: AppColor.textPrimary
        case .button: AppColor.accent
        }
    }
}

extension View {
    /// Применяет шрифт и цвет семантической роли текста.
    func textStyle(_ style: AppTextStyle) -> some View {
        font(style.font).foregroundStyle(style.color)
    }
}
