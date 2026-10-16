// LedgerFixture.swift
// Наборы демонстрационных данных для previews и изолированного режима UI-тестов.
// В обычном запуске приложения не используются: AppDependencies применяет fixture только к временной БД.

// Foundation нужен для UUID, Date и ProcessInfo.
import Foundation
// SwiftData нужен для ModelContainer и ModelContext.
import SwiftData

/// Набор демонстрационных данных.
nonisolated enum LedgerFixture: String, CaseIterable, Sendable {
    /// Расходы за последние ~4 месяца: много категорий, длинная история, длинные комментарии,
    /// архивные категории и расход категории, которой нет на устройстве.
    case filled
    /// Расходы только за прошлый месяц: текущий месяц пустой.
    case previousMonthOnly

    /// Аргумент запуска, после которого идёт имя набора: `--ui-fixture filled`.
    static let launchArgument = "--ui-fixture"

    /// UUID категории, которой нет на устройстве (данные, пришедшие раньше категории).
    static let missingCategoryID = UUID(uuidString: "0F1E2D3C-4B5A-4978-8899-AABBCCDDEEFF")!

    /// Набор из аргументов запуска процесса; `nil`, если аргумента нет.
    static func detect(processInfo: ProcessInfo = .processInfo) -> LedgerFixture? {
        let arguments = processInfo.arguments // Аргументы процесса.
        guard let index = arguments.firstIndex(of: launchArgument), index + 1 < arguments.count else { return nil } // Аргумента нет.
        return LedgerFixture(rawValue: arguments[index + 1]) // Имя набора.
    }

    /// Наполняет хранилище через те же методы, что использует приложение.
    /// - Parameters:
    ///   - ledger: хранилище временной БД.
    ///   - container: контейнер той же БД (для записи расхода без категории на устройстве).
    ///   - today: «сегодня» для расчёта дат.
    func seed(into ledger: LedgerStore, container: ModelContainer, today: CalendarDate) async throws {
        switch self { // Набор данных.
        case .filled: try await Self.seedFilled(ledger: ledger, container: container, today: today) // Полный набор.
        case .previousMonthOnly: try await Self.seedPreviousMonth(ledger: ledger, today: today) // Только прошлый месяц.
        }
    }

    /// Комментарии расходов; `nil` — без комментария.
    private static let comments: [String?] = [
        "Ужин с подругами", nil, "TEREMOK", "COFFEE LIKE", nil, "ВКУСВИЛЛ", "Обед с коллегами", "OZON", nil,
        "Такси до аэропорта после позднего рейса, ждали машину почти сорок минут", "STARBUCKS", nil,
    ]

    /// Суммы в копейках по кругу.
    private static let amounts: [Int64] = [32_000, 18_550, 245_000, 54_000, 120_000, 9_900, 387_000, 2_450_00, 65_050, 1_250_00, 30_000, 7_499_00]

    /// Полный набор: ~4 месяца расходов.
    private static func seedFilled(ledger: LedgerStore, container: ModelContainer, today: CalendarDate) async throws {
        // Своя категория с коротким названием.
        let coffee = try await ledger.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 4))
        // Своя категория с названием предельной длины (24 символа).
        let courses = try await ledger.createCategory(NewCategory(name: "Курсы и самообразование!", emoji: "📚", colorIndex: 5))
        // Своя категория, которую позже архивируют.
        let pool = try await ledger.createCategory(NewCategory(name: "Бассейн", emoji: "🏊", colorIndex: 6))
        // Категории, по которым распределяются расходы.
        let categoryIDs = SystemCategory.allCases.map(\.id) + [coffee.id, courses.id, pool.id]
        for offset in 0..<120 { // Дни от сегодня назад.
            // День расхода.
            let date = try today.adding(days: -offset)
            for index in 0..<(1 + offset % 3) { // 1–3 расхода в день.
                // Номер расхода для детерминированного выбора полей.
                let seed = offset * 3 + index
                _ = try await ledger.createExpense(ExpenseDraft( // Обычный расход.
                    amount: Money(minorUnits: amounts[seed % amounts.count]), // Сумма по кругу.
                    categoryID: categoryIDs[(seed * 7 + offset) % categoryIDs.count], // Категория по кругу.
                    date: date, // День.
                    comment: comments[seed % comments.count] // Комментарий или nil.
                ))
            }
        }
        // Длинный комментарий предельной длины (200 символов).
        let longComment = String(repeating: "Очень длинный комментарий к покупке. ", count: 6).prefix(200)
        _ = try await ledger.createExpense(ExpenseDraft(amount: Money(minorUnits: 1_999_00), categoryID: SystemCategory.home.id, date: today, comment: String(longComment))) // Длинный комментарий сегодня.
        _ = try await ledger.archiveCategory(id: pool.id) // Архивная своя категория с расходами.
        _ = try await ledger.archiveCategory(id: SystemCategory.gifts.id) // Архивная системная категория с расходами.
        try await MainActor.run { // Расход без категории на устройстве: так его применил бы будущий sync.
            // Отдельный контекст той же БД.
            let context = ModelContext(container)
            context.insert(Expense( // Расход ссылается на неизвестную категорию.
                id: UUID(), amountMinorUnits: 4_200_00, categoryID: missingCategoryID, // Сумма и неизвестная категория.
                dateKey: today.storageKey, comment: "Перевод из приложения банка", now: .now // Сегодня, с комментарием.
            ))
            try context.save() // Запись в БД.
        }
    }

    /// Набор только за прошлый месяц.
    private static func seedPreviousMonth(ledger: LedgerStore, today: CalendarDate) async throws {
        // Прошлый месяц целиком.
        let month = ExpensePeriod(preset: .previousMonth, today: today).interval
        for (index, category) in [SystemCategory.products, .cafe, .transport].enumerated() { // Три категории.
            _ = try await ledger.createExpense(ExpenseDraft( // Расход в прошлом месяце.
                amount: Money(minorUnits: amounts[index]), // Сумма.
                categoryID: category.id, // Категория.
                date: try month.lowerBound.adding(days: index * 5), // Дата внутри месяца.
                comment: comments[index] // Комментарий или nil.
            ))
        }
    }
}
