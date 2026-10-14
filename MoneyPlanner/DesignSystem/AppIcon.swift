import SwiftUI

/// Каталог семантических иконок SF Symbols.
///
/// Строковые имена символов живут только здесь. Экран выбирает иконку по смыслу:
/// `AppIcon.retry.image`, `Label(…, systemImage: AppIcon.retry.systemName)`.
/// Растровые и векторные изображения добавляются в Asset Catalog и используются через `ImageResource`.
enum AppIcon: String, CaseIterable {
    case retry = "arrow.clockwise"
    case error = "exclamationmark.triangle"
    case noConnection = "wifi.slash"
    case storage = "internaldrive"
    case server = "server.rack"
    case success = "checkmark.circle.fill"
    case failure = "xmark.octagon.fill"
    case notConfigured = "slash.circle"

    var systemName: String { rawValue }

    var image: Image { Image(systemName: rawValue) }
}
