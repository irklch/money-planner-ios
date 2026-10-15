// AppMetrics.swift
// Шкалы отступов, радиусов, размеров иконок и стандартных размеров элементов.

// CoreGraphics нужен для типа CGFloat.
import CoreGraphics

/// Шкала отступов. Используется для padding и spacing вместо чисел в экранах.
/// Значения предварительные, до утверждения макета в Figma.
enum AppSpacing {
    /// 4 pt — минимальный зазор между связанными элементами.
    static let xxSmall: CGFloat = 4
    /// 8 pt — зазор внутри компактных групп.
    static let xSmall: CGFloat = 8
    /// 12 pt — зазор между элементами строки.
    static let small: CGFloat = 12
    /// 16 pt — стандартный внешний отступ экрана.
    static let medium: CGFloat = 16
    /// 24 pt — отступ между блоками.
    static let large: CGFloat = 24
    /// 32 pt — отступ между крупными секциями.
    static let xLarge: CGFloat = 32
}

/// Радиусы скругления.
enum AppRadius {
    /// 8 pt — мелкие элементы: бейджи, иконки категорий.
    static let small: CGFloat = 8
    /// 16 pt — карточки.
    static let medium: CGFloat = 16
    /// 24 pt — крупные контейнеры.
    static let large: CGFloat = 24
}

/// Базовые размеры иконок. Внутри View масштабируются через `@ScaledMetric(relativeTo:)`.
enum AppIconSize {
    /// 20 pt — иконка в строке списка.
    static let small: CGFloat = 20
    /// 28 pt — иконка в заголовке блока.
    static let medium: CGFloat = 28
    /// 48 pt — иконка состояния (ошибка, пустой экран).
    static let large: CGFloat = 48
}

/// Стандартные размеры элементов.
enum AppSize {
    /// Минимальная область касания по Human Interface Guidelines.
    static let minimumTapTarget: CGFloat = 44
}
