// AppIcon.swift
// Каталог семантических иконок SF Symbols: единственное место, где хранятся строковые имена символов.

// SwiftUI нужен для типа Image.
import SwiftUI

/// Каталог семантических иконок SF Symbols.
///
/// Строковые имена символов живут только здесь. Экран выбирает иконку по смыслу:
/// `AppIcon.retry.image`, `Label(…, systemImage: AppIcon.retry.systemName)`.
/// Растровые и векторные изображения добавляются в Asset Catalog и используются через `ImageResource`.
/// Категории SF Symbols не используют: их идентичность — эмодзи (Figma, Category identity).
enum AppIcon: String, CaseIterable {
    /// Повторить действие.
    case retry = "arrow.clockwise"
    /// Общая ошибка или предупреждение.
    case error = "exclamationmark.triangle"
    /// Нет соединения с сетью.
    case noConnection = "wifi.slash"
    /// Переход в строке списка.
    case disclosure = "chevron.right"
    /// Открывает выбор из вариантов (капсула периода).
    case selector = "chevron.up.chevron.down"
    /// Выбранный вариант.
    case checkmark = "checkmark"
    /// Календарь: пустой период.
    case calendar = "calendar"
    /// Категория, которой нет на устройстве.
    case unknownCategory = "questionmark"

    /// Имя символа SF Symbols для API, которые принимают строку (`Label(systemImage:)`).
    var systemName: String { rawValue } // Имя символа хранится как rawValue кейса.

    /// Готовое изображение символа.
    var image: Image { Image(systemName: rawValue) } // Создаём Image из имени символа.
}
