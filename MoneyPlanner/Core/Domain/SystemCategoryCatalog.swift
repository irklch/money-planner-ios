// SystemCategoryCatalog.swift
// Утверждённые системные категории MVP: реестр `contract/system-categories.json` бэкенда
// (статус approved, 11.10.2026). Определения — константы приложения, в sync передаётся только состояние.

// Foundation нужен для UUID и LocalizedStringResource.
import Foundation

/// Системная категория из реестра `SYSTEM_CATEGORY_IDS`.
///
/// UUID стабильны навсегда и совпадают между установками и платформами: их нельзя
/// генерировать при запуске, менять или удалять. Название берётся из String Catalog
/// по ключу `category.system.<key>`.
nonisolated enum SystemCategory: String, CaseIterable, Sendable {
    /// Продукты.
    case products
    /// Кафе и рестораны.
    case cafe
    /// Транспорт.
    case transport
    /// Дом и ЖКХ.
    case home
    /// Здоровье.
    case health
    /// Одежда и обувь.
    case clothes
    /// Развлечения.
    case entertainment
    /// Связь и подписки.
    case telecom
    /// Красота.
    case beauty
    /// Подарки.
    case gifts
    /// Путешествия.
    case travel
    /// Другое — резервная категория, не архивируется.
    case other

    /// Резервная категория «Другое» (`fallbackCategoryId` реестра).
    static let fallback = SystemCategory.other

    /// Стабильный UUID из реестра.
    var id: UUID {
        UUID(uuidString: idString)! // Строки реестра — корректные UUID.
    }

    /// UUID из реестра в каноническом виде контракта.
    var idString: String {
        switch self { // Значения из `contract/system-categories.json`.
        case .products: "00000000-0000-4000-8000-000000000001" // Продукты.
        case .cafe: "00000000-0000-4000-8000-000000000002" // Кафе и рестораны.
        case .transport: "00000000-0000-4000-8000-000000000003" // Транспорт.
        case .home: "00000000-0000-4000-8000-000000000004" // Дом и ЖКХ.
        case .health: "00000000-0000-4000-8000-000000000005" // Здоровье.
        case .clothes: "00000000-0000-4000-8000-000000000006" // Одежда и обувь.
        case .entertainment: "00000000-0000-4000-8000-000000000007" // Развлечения.
        case .telecom: "00000000-0000-4000-8000-000000000008" // Связь и подписки.
        case .beauty: "00000000-0000-4000-8000-000000000009" // Красота.
        case .gifts: "00000000-0000-4000-8000-00000000000a" // Подарки.
        case .travel: "00000000-0000-4000-8000-00000000000b" // Путешествия.
        case .other: "00000000-0000-4000-8000-000000000099" // Другое.
        }
    }

    /// Эмодзи категории.
    var emoji: String {
        switch self { // Значения из реестра.
        case .products: "🛒" // Продукты.
        case .cafe: "🍽️" // Кафе и рестораны.
        case .transport: "🚕" // Транспорт.
        case .home: "🏠" // Дом и ЖКХ.
        case .health: "💊" // Здоровье.
        case .clothes: "👕" // Одежда и обувь.
        case .entertainment: "🎬" // Развлечения.
        case .telecom: "📱" // Связь и подписки.
        case .beauty: "💅" // Красота.
        case .gifts: "🎁" // Подарки.
        case .travel: "✈️" // Путешествия.
        case .other: "📦" // Другое.
        }
    }

    /// Индекс цвета в `CategoryPalette` (0–11).
    var colorIndex: Int {
        switch self { // Значения из реестра.
        case .products: 0 // Продукты.
        case .cafe: 1 // Кафе и рестораны.
        case .transport: 2 // Транспорт.
        case .home: 3 // Дом и ЖКХ.
        case .health: 4 // Здоровье.
        case .clothes: 5 // Одежда и обувь.
        case .entertainment: 6 // Развлечения.
        case .telecom: 7 // Связь и подписки.
        case .beauty: 8 // Красота.
        case .gifts: 9 // Подарки.
        case .travel: 10 // Путешествия.
        case .other: 11 // Другое.
        }
    }

    /// Порядок в списке категорий.
    var sortOrder: Int {
        self == .other ? 99 : SystemCategory.allCases.firstIndex(of: self)! + 1 // 1–11, «Другое» — 99.
    }

    /// Можно ли архивировать категорию: все, кроме «Другое».
    var isArchivable: Bool { self != .fallback } // План §3.2.

    /// Локализованное название из String Catalog. MainActor: символы каталога генерируются на нём,
    /// а название нужно только интерфейсу.
    @MainActor var name: LocalizedStringResource {
        switch self { // Ключи `category.system.<key>`.
        case .products: .categorySystemProducts // «Продукты».
        case .cafe: .categorySystemCafe // «Кафе и рестораны».
        case .transport: .categorySystemTransport // «Транспорт».
        case .home: .categorySystemHome // «Дом и ЖКХ».
        case .health: .categorySystemHealth // «Здоровье».
        case .clothes: .categorySystemClothes // «Одежда и обувь».
        case .entertainment: .categorySystemEntertainment // «Развлечения».
        case .telecom: .categorySystemTelecom // «Связь и подписки».
        case .beauty: .categorySystemBeauty // «Красота».
        case .gifts: .categorySystemGifts // «Подарки».
        case .travel: .categorySystemTravel // «Путешествия».
        case .other: .categorySystemOther // «Другое».
        }
    }

    /// Системная категория по UUID; `nil`, если UUID не из реестра.
    init?(id: UUID) {
        guard let match = Self.allCases.first(where: { $0.id == id }) else { return nil } // Поиск в реестре.
        self = match // Найденная категория.
    }
}
