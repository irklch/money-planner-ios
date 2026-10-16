// AppColor.swift
// Типизированный доступ к цветам дизайн-системы и палитре категорий.
// Сами значения цветов хранятся только в Resources/Assets.xcassets.

// SwiftUI нужен для типа Color.
import SwiftUI

/// Семантические цвета приложения.
///
/// Значения задаются только в `Resources/Assets.xcassets` (папка `Colors` и `AccentColor`),
/// здесь — единственная точка доступа к ним из кода. Экраны не создают `Color` из HEX/RGB.
/// Значения — токены Figma «FINAL UI · MVP», Foundations (узел `132:67`), только светлая тема.
enum AppColor {
    /// Фон всех экранов и sheets (`background/primary`).
    static let background = Color(.background) // Цвет из ассета Colors/Background.
    /// Подложка эмодзи в строках истории (`background/secondary`).
    static let backgroundSecondary = Color(.backgroundSecondary) // Цвет из ассета Colors/BackgroundSecondary.
    /// Карточки, строки списка и другие поверхности поверх фона (`surface/primary`).
    static let surface = Color(.surface) // Цвет из ассета Colors/Surface.
    /// Мягкая нейтральная подложка: бейдж эмодзи категории, сегмент «Ещё N» (`surface/secondary`).
    static let surfaceSecondary = Color(.surfaceSecondary) // Цвет из ассета Colors/SurfaceSecondary.
    /// Основной текст (`text/primary`).
    static let textPrimary = Color(.textPrimary) // Цвет из ассета Colors/TextPrimary.
    /// Вторичный текст: подписи, пояснения (`text/secondary`).
    static let textSecondary = Color(.textSecondary) // Цвет из ассета Colors/TextSecondary.
    /// Третичный текст и chevron: знак валюты в итоге, служебные стрелки (`text/tertiary`).
    static let textTertiary = Color(.textTertiary) // Цвет из ассета Colors/TextTertiary.
    /// Акцент: основные действия и выделение. Совпадает с глобальным tint приложения (`accent/primary`).
    static let accent = Color(.accent) // Цвет из ассета AccentColor (он же tint приложения).
    /// Тёплое свечение фона главного экрана (`accent/glow`).
    static let accentGlow = Color(.accentGlow) // Цвет из ассета Colors/AccentGlow.
    /// Разделители и тонкие границы (`border/separator`).
    static let separator = Color(.separator) // Цвет из ассета Colors/Separator.
    /// Ошибки и деструктивные состояния (`status/error`).
    static let error = Color(.error) // Цвет из ассета Colors/Error.
    /// Успешное состояние (`status/success`).
    static let success = Color(.success) // Цвет из ассета Colors/Success.
}

/// Палитра системных и пользовательских категорий.
///
/// Индекс соответствует `colorIndex` категории в контракте бэкенда (0–11, `category_palette_size = 12`).
/// Значения — `category/01-tangerine` … `category/12-coral` из Figma. Цвет категории используется
/// только для сегмента полосы и точки рядом с долей, не для фона карточек и текста.
enum CategoryPalette {
    /// Цвета палитры в порядке индексов 0–11.
    static let colors: [Color] = [
        Color(.category00), Color(.category01), Color(.category02), Color(.category03), // Индексы 0–3.
        Color(.category04), Color(.category05), Color(.category06), Color(.category07), // Индексы 4–7.
        Color(.category08), Color(.category09), Color(.category10), Color(.category11), // Индексы 8–11.
    ]

    /// Нейтральный цвет категории, которой нет на устройстве (`category/other`).
    static let unknown = Color(.categoryUnknown) // Цвет из ассета CategoryPalette/CategoryUnknown.

    /// Цвет по индексу палитры. Индекс вне диапазона сворачивается по модулю,
    /// чтобы неизвестное значение с сервера не приводило к падению.
    static func color(at index: Int) -> Color {
        let count = colors.count // Размер палитры для вычисления остатка.
        return colors[((index % count) + count) % count] // Остаток всегда в 0..<count, в том числе для отрицательных индексов.
    }
}
