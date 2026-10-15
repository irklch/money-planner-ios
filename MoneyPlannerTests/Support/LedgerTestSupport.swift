// LedgerTestSupport.swift
// Общие средства тестов слоя данных: fixtures контракта, управляемые часы и управляемое сохранение.

// Foundation нужен для Date, Data, Bundle и JSONDecoder.
import Foundation
// SwiftData нужен для ModelContext.
import SwiftData
// Synchronization нужен для Mutex: состояние тестовых часов и сохранения читается из актора.
import Synchronization
// Testing нужен для #require в загрузке fixtures.
import Testing
@testable import MoneyPlanner // Доступ к внутренним типам приложения.

/// Fixtures из `contract/` бэкенда `money-planner-backend` @ 36ce86b0956c5297b16776087b8869ad1df64818.
///
/// Файлы скопированы без изменений в `MoneyPlannerTests/Fixtures/Contract/`:
/// `vectors/comment.json` → `comment-vectors.json`, `vectors/day-mark-id.json` → `day-mark-id-vectors.json`,
/// `system-categories.json`. При обновлении контракта их нужно скопировать заново.
enum ContractFixtures {
    /// Маркер тестового бандла.
    private final class BundleToken {}

    /// Декодирует fixture из ресурсов тестового бандла через `JSONDecoder`.
    static func load<Value: Decodable>(_ type: Value.Type, named name: String) throws -> Value {
        // URL ресурса в бандле тестов.
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url)) // JSONDecoder сохраняет ведущий U+FEFF.
    }
}

/// Управляемый источник времени; безопасен для вызова из актора.
final class StoreTestClock: Sendable {
    /// Текущий момент.
    private let value: Mutex<Date>

    /// Создаёт часы с начальным моментом.
    init(_ start: Date) {
        value = Mutex(start) // Начальный момент под замком.
    }

    /// Текущий момент.
    var now: Date { value.withLock { $0 } }

    /// Устанавливает момент.
    func set(_ date: Date) {
        value.withLock { $0 = date } // Новый момент.
    }

    /// Сдвигает момент на `seconds`.
    func advance(by seconds: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) } // Сдвиг вперёд или назад.
    }
}

/// Ошибка, которой тест имитирует сбой записи БД.
struct SimulatedStoreSaveError: Error, Equatable {}

/// Операция сохранения для тестов: настоящий `ModelContext.save()` или ошибка по требованию.
///
/// Ошибка выбрасывается до записи, поэтому несохранённые изменения остаются в контексте,
/// и тест проверяет реальный откат через `ModelContext.rollback()` в хранилище.
final class ControlledStoreSave: Sendable {
    /// Состояние: число предстоящих ошибок и число имитированных.
    private let state = Mutex((pending: 0, failed: 0))

    /// Следующие `count` сохранений завершатся ошибкой.
    func failNext(_ count: Int = 1) {
        state.withLock { $0.pending = count } // Сколько сохранений подряд упадёт.
    }

    /// Число имитированных ошибок.
    var failedSaves: Int { state.withLock { $0.failed } }

    /// Сохраняет контекст или выбрасывает `SimulatedStoreSaveError`.
    func save(_ context: ModelContext) throws {
        // Нужно ли сейчас выбросить ошибку.
        let shouldFail = state.withLock { state -> Bool in
            guard state.pending > 0 else { return false } // Ошибок больше не запланировано.
            state.pending -= 1 // Одна запланированная ошибка израсходована.
            state.failed += 1 // Учитываем сработавшую ошибку.
            return true // Это сохранение должно упасть.
        }
        if shouldFail { throw SimulatedStoreSaveError() } // Ошибка до записи: изменения остаются в контексте.
        try context.save() // Настоящее сохранение.
    }
}

extension CalendarDate { // Удобный конструктор дат для тестов.
    /// Дата из литерала для тестов; некорректная строка — ошибка теста.
    static func iso(_ text: String) -> CalendarDate {
        try! CalendarDate(isoString: text) // Литерал теста всегда корректен.
    }
}

extension Money { // Удобный конструктор сумм для тестов.
    /// Сумма из decimal-строки для тестов.
    static func api(_ text: String) -> Money {
        try! Money(apiString: text) // Литерал теста всегда корректен.
    }
}
