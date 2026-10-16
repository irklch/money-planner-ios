// AppMetrics.swift
// Шкалы отступов, радиусов, размеров иконок и стандартных размеров элементов.

// CoreGraphics нужен для типа CGFloat.
import CoreGraphics

/// Шкала отступов (кратна 2–4 pt). Используется для padding и spacing вместо чисел в экранах.
/// Значения — Figma «FINAL UI · MVP», Spacing & Radius: поля экрана 16 (карточки) и 20 (заголовки),
/// между секциями 28, внутри карточки 16.
enum AppSpacing {
    /// 2 pt — шов между сегментами полосы распределения.
    static let tiny: CGFloat = 2
    /// 4 pt — минимальный зазор между связанными элементами.
    static let xxSmall: CGFloat = 4
    /// 6 pt — зазор подписи и суммы в итоге.
    static let compact: CGFloat = 6
    /// 8 pt — зазор внутри компактных групп.
    static let xSmall: CGFloat = 8
    /// 10 pt — отступ строки категории, внутренний отступ эмодзи в заголовке.
    static let snug: CGFloat = 10
    /// 12 pt — зазор между элементами строки.
    static let small: CGFloat = 12
    /// 14 pt — отступ текста в капсуле выбора периода.
    static let cozy: CGFloat = 14
    /// 16 pt — поле экрана для карточек и внутренний отступ карточки.
    static let medium: CGFloat = 16
    /// 20 pt — поле экрана для текстовых заголовков.
    static let mediumLarge: CGFloat = 20
    /// 24 pt — отступ между блоками.
    static let large: CGFloat = 24
    /// 28 pt — отступ между секциями экрана.
    static let section: CGFloat = 28
    /// 32 pt — отступ между крупными секциями.
    static let xLarge: CGFloat = 32
    /// 40 pt — отступ после итоговой суммы.
    static let xxLarge: CGFloat = 40
}

/// Радиусы скругления (`radius/*` в Figma).
enum AppRadius {
    /// 6 pt — полоса распределения.
    static let bar: CGFloat = 6
    /// 10 pt — бейдж эмодзи категории в строке.
    static let small: CGFloat = 10
    /// 16 pt — группа строк истории, эмодзи в заголовке категории.
    static let medium: CGFloat = 16
    /// 24 pt — карточки и списки (`radius/lg`).
    static let large: CGFloat = 24
}

/// Базовые размеры иконок и эмодзи. Внутри View масштабируются через `@ScaledMetric(relativeTo:)`.
enum AppIconSize {
    /// 14 pt — chevron и стрелки в строках.
    static let chevron: CGFloat = 14
    /// 20 pt — эмодзи в бейдже категории.
    static let small: CGFloat = 20
    /// 28 pt — эмодзи в заголовке экрана категории.
    static let medium: CGFloat = 28
    /// 30 pt — символ пустого состояния.
    static let emptyState: CGFloat = 30
    /// 48 pt — иконка состояния ошибки.
    static let large: CGFloat = 48
}

/// Стандартные размеры элементов.
enum AppSize {
    /// Минимальная область касания по Human Interface Guidelines.
    static let minimumTapTarget: CGFloat = 44
    /// Сторона бейджа эмодзи категории (Category / Emoji M).
    static let categoryBadge: CGFloat = 36
    /// Сторона подложки символа пустого состояния.
    static let emptyStateBadge: CGFloat = 64
    /// Диаметр точки цвета категории рядом с долей.
    static let categoryDot: CGFloat = 8
    /// Высота полосы распределения на главном экране.
    static let distributionBar: CGFloat = 14
    /// Высота капсулы выбора периода.
    static let periodMenu: CGFloat = 36
    /// Высота строки варианта в списке выбора.
    static let optionRow: CGFloat = 50
    /// Толщина разделителя.
    static let hairline: CGFloat = 0.5
}
