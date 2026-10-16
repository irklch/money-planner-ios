// AppTypography.swift
// Семантические роли текста: шрифт и цвет по умолчанию для каждой роли.

// SwiftUI нужен для Font, Color и модификатора View.
import SwiftUI

/// Семантические роли текста.
///
/// Каждая роль опирается на системный text style (SF Pro), поэтому масштабируется Dynamic Type.
/// Экраны выбирают роль через `.textStyle(_:)`, а не задают шрифт напрямую.
/// Роли повторяют текстовые стили Figma «iOS / …» (Inter на канвасе — прокси SF Pro).
enum AppTextStyle: CaseIterable {
    /// Крупный заголовок экрана (`iOS / Large Title`, 34 Bold).
    case screenTitle
    /// Заголовок экрана категории и сумма категории (`iOS / Title 1`, 28 Bold).
    case title
    /// Заголовок пустого состояния (`iOS / Title 2`, 22 Bold).
    case stateTitle
    /// Заголовок секции (`iOS / Title 3`, 20 Semibold).
    case sectionTitle
    /// Заголовок sheet (`iOS / Headline`, 17 Semibold).
    case headline
    /// Основной текст (`iOS / Body`, 17).
    case body
    /// Пояснение и подпись итога (`iOS / Subheadline`, 15).
    case subheadline
    /// Текст капсулы выбора периода (`iOS / Subheadline Emphasized`, 15 Semibold).
    case subheadlineEmphasized
    /// Подпись, вторичная информация (`iOS / Footnote`, 13).
    case caption
    /// Заголовок дня в истории (`iOS / Footnote Emphasized`, 13 Semibold).
    case captionEmphasized
    /// Сумма в списках (`iOS / Body Emphasized`, 17 Medium): цифры одинаковой ширины.
    case amount
    /// Текст кнопки.
    case button

    /// Шрифт роли: системный text style и начертание.
    var font: Font {
        switch self { // Выбираем шрифт по роли.
        case .screenTitle: .system(.largeTitle, weight: .bold) // 34 Bold.
        case .title: .system(.title, weight: .bold) // 28 Bold.
        case .stateTitle: .system(.title2, weight: .bold) // 22 Bold.
        case .sectionTitle: .system(.title3, weight: .semibold) // 20 Semibold.
        case .headline: .system(.headline, weight: .semibold) // 17 Semibold.
        case .body: .system(.body) // 17 Regular.
        case .subheadline: .system(.subheadline) // 15 Regular.
        case .subheadlineEmphasized: .system(.subheadline, weight: .semibold) // 15 Semibold.
        case .caption: .system(.footnote) // 13 Regular.
        case .captionEmphasized: .system(.footnote, weight: .semibold) // 13 Semibold.
        case .amount: .system(.body, weight: .medium).monospacedDigit() // 17 Medium, суммы не «прыгают».
        case .button: .system(.body, weight: .semibold) // 17 Semibold.
        }
    }

    /// Цвет по умолчанию для роли.
    var color: Color {
        switch self { // Выбираем цвет по роли.
        case .subheadline, .caption, .captionEmphasized: AppColor.textSecondary // Подписи — вторичным цветом.
        case .button: AppColor.accent // Кнопки — акцентным цветом.
        case .screenTitle, .title, .stateTitle, .sectionTitle, .headline, .body, .subheadlineEmphasized, .amount: AppColor.textPrimary // Основной текст.
        }
    }
}

/// Итоговая сумма периода (`iOS / Hero / Amount`, 56 Medium).
///
/// Отдельного системного text style такого размера нет: размер масштабируется относительно
/// `.largeTitle` через `@ScaledMetric`, поэтому Dynamic Type работает.
struct HeroAmountFont: ViewModifier {
    /// Базовый размер 56 pt, масштабируемый вместе с `.largeTitle`.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56

    /// Применяет шрифт итоговой суммы.
    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .medium).monospacedDigit()) // Крупные цифры одинаковой ширины.
            .foregroundStyle(AppColor.textPrimary) // Цифры — основным цветом.
    }
}

/// Применение ролей текста к любому View.
extension View {
    /// Применяет шрифт и цвет семантической роли текста.
    func textStyle(_ style: AppTextStyle) -> some View {
        font(style.font).foregroundStyle(style.color) // Задаём шрифт роли и её цвет по умолчанию.
    }

    /// Применяет шрифт итоговой суммы периода.
    func heroAmountStyle() -> some View {
        modifier(HeroAmountFont()) // Масштабируемый размер 56 pt.
    }
}
