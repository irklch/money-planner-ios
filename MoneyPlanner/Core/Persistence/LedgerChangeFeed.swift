// LedgerChangeFeed.swift
// Единый механизм оповещения экранов об изменении локальных данных: без polling и таймеров.

// Foundation нужен для UUID.
import Foundation
// Synchronization нужен для Mutex: подписки меняются из разных изоляций.
import Synchronization

/// Рассылка «данные изменились» всем подписчикам.
///
/// `LedgerStore` вызывает `notify()` после каждой успешно сохранённой транзакции
/// (создание, изменение, удаление расходов, правка категорий, отметки дня, а в будущем —
/// применение данных sync). Экран подписывается на время показа и перечитывает сводку.
/// Буфер — одно последнее событие: серия изменений во время чтения даёт одно перечитывание.
nonisolated final class LedgerChangeFeed: Sendable {
    /// Активные подписки по ключу.
    private let subscribers = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    /// Создаёт рассылку без подписчиков.
    init() {}

    /// Новая подписка. Завершается, когда задача-подписчик отменена или поток освобождён.
    func changes() -> AsyncStream<Void> {
        // Поток и его продолжение; хранится только последнее событие.
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // Ключ подписки.
        let key = UUID()
        subscribers.withLock { $0[key] = continuation } // Регистрируем подписку.
        continuation.onTermination = { [weak self] _ in // Отмена задачи или освобождение потока.
            self?.subscribers.withLock { _ = $0.removeValue(forKey: key) } // Подписка больше не нужна.
        }
        return stream // Поток событий для `for await`.
    }

    /// Сообщает всем подписчикам, что данные изменились.
    func notify() {
        // Снимок подписок вне замка: yield не должен выполняться под замком.
        let current = subscribers.withLock { Array($0.values) }
        current.forEach { $0.yield() } // Событие каждому подписчику.
    }

    /// Число активных подписок (для тестов отмены).
    var subscriberCount: Int { subscribers.withLock { $0.count } }
}
