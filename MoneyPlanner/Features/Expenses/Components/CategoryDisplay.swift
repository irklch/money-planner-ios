// CategoryDisplay.swift
// Отображение категории: название, цвет и бейдж эмодзи (Figma, Category identity и Category / Emoji `134:17`).

// SwiftUI нужен для View, Text и Color.
import SwiftUI

/// Отображаемые свойства категории.
extension CategoryReference {
    /// Название: системное — из String Catalog, пользовательское — как ввёл пользователь, неизвестное — плейсхолдер.
    var title: Text {
        switch self { // Источник названия.
        case .known(let category): // Категория есть на устройстве.
            switch category.title { // Системная или пользовательская.
            case .system(let system): Text(system.name) // Локализованное название реестра.
            case .user(let name): Text(verbatim: name) // Пользовательское название не локализуется.
            }
        case .unknown: Text(.categoryUnknown) // «Без категории».
        }
    }

    /// Название строкой (для VoiceOver и заголовков).
    var titleString: String {
        switch self { // Источник названия.
        case .known(let category): // Категория есть на устройстве.
            switch category.title { // Системная или пользовательская.
            case .system(let system): String(localized: system.name) // Локализованное название реестра.
            case .user(let name): name // Как ввёл пользователь.
            }
        case .unknown: String(localized: .categoryUnknown) // «Без категории».
        }
    }

    /// Цвет категории для сегмента полосы и точки.
    var color: Color {
        switch self { // Цвет по палитре.
        case .known(let category): CategoryPalette.color(at: category.colorIndex) // Индекс палитры.
        case .unknown: CategoryPalette.unknown // Нейтральный цвет.
        }
    }

    /// Эмодзи категории; `nil` для неизвестной категории.
    var emoji: String? {
        if case .known(let category) = self { return category.emoji } // Эмодзи — данные категории.
        return nil // У неизвестной категории эмодзи нет.
    }
}

/// Бейдж категории: эмодзи на мягкой нейтральной подложке, без цвета категории.
struct CategoryBadge: View {
    /// Вид подложки.
    enum Style {
        /// Обзор категорий: `surface/secondary` с тонкой обводкой.
        case outlined
        /// Строка истории: `background/secondary` без обводки.
        case filled
    }

    /// Категория.
    let category: CategoryReference
    /// Вид подложки.
    var style: Style = .outlined

    /// Сторона бейджа, масштабируемая вместе с текстом.
    @ScaledMetric(relativeTo: .body) private var side = AppSize.categoryBadge
    /// Размер эмодзи, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .body) private var glyph = AppIconSize.small

    /// Наибольшая сторона: при специальных размерах текста бейдж не отнимает место у названия.
    private let maxSide = AppSize.categoryBadge * 1.5

    /// Содержимое бейджа.
    var body: some View {
        // Форма подложки.
        let shape = RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
        Group { // Эмодзи или символ неизвестной категории.
            if let emoji = category.emoji { // Эмодзи категории.
                Text(verbatim: emoji).font(.system(size: min(glyph, maxSide * 0.55))) // Эмодзи не локализуется.
            } else {
                AppIcon.unknownCategory.image // Символ «?».
                    .font(.system(size: min(glyph, maxSide * 0.55) * 0.8, weight: .semibold)) // Символ чуть меньше эмодзи.
                    .foregroundStyle(AppColor.textSecondary) // Вторичный цвет.
            }
        }
        .frame(width: min(side, maxSide), height: min(side, maxSide)) // Квадрат 36 pt; при крупном тексте растёт ограниченно.
        .background(style == .outlined ? AppColor.surfaceSecondary : AppColor.backgroundSecondary, in: shape) // Подложка.
        .overlay { // Обводка только у варианта обзора.
            if style == .outlined { shape.stroke(AppColor.separator, lineWidth: 1) } // Тонкая граница.
        }
        .accessibilityHidden(true) // Название категории читается текстом строки.
    }
}

/// Точка цвета категории рядом с долей.
struct CategoryDot: View {
    /// Цвет категории.
    let color: Color

    /// Диаметр точки, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .footnote) private var diameter = AppSize.categoryDot

    /// Содержимое точки.
    var body: some View {
        Circle().fill(color).frame(width: diameter, height: diameter).accessibilityHidden(true) // Декоративная точка.
    }
}

/// Шеврон перехода в строке.
struct DisclosureChevron: View {
    /// Размер символа, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .body) private var size = AppIconSize.chevron

    /// Содержимое шеврона.
    var body: some View {
        AppIcon.disclosure.image // chevron.right.
            .font(.system(size: size, weight: .semibold)) // 14 pt.
            .foregroundStyle(AppColor.textTertiary) // Третичный цвет.
            .accessibilityHidden(true) // Переход объявляет сама кнопка.
    }
}

/// Расположение строки: по горизонтали, а при крупном Dynamic Type — по вертикали.
struct AdaptiveRowLayout {
    /// Размер шрифта среды.
    let dynamicTypeSize: DynamicTypeSize

    /// Горизонтальный ряд или вертикальный столбец для специальных размеров.
    var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxSmall)) // Сумма под названием.
            : AnyLayout(HStackLayout(spacing: AppSpacing.small)) // Сумма справа.
    }
}
