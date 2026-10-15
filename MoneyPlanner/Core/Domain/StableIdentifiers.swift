// StableIdentifiers.swift
// Детерминированные идентификаторы, общие для всех установок и платформ:
// UUIDv5 отметки дня (план §4) и запись UUID в каноническом виде контракта.

// CryptoKit нужен для SHA-1 в алгоритме UUIDv5 (RFC 9562).
import CryptoKit
// Foundation нужен для UUID и Data.
import Foundation

/// Идентификатор отметки «День без расходов»: `UUIDv5(NS_DAY_MARK, "YYYY-MM-DD")`.
nonisolated enum DayMarkID {
    /// Пространство имён `NS_DAY_MARK` (`x-contract.dayMarkNamespace`).
    static let namespace = UUID(uuidString: "97a5414e-31da-4b51-85c7-7ea3eab0c81d")!

    /// `entityId` отметки для даты. Совпадает на всех устройствах и на сервере.
    static func make(for date: CalendarDate) -> UUID {
        UUID.version5(namespace: namespace, name: date.isoString) // Имя — дата в ASCII без пробелов.
    }
}

extension UUID { // Расширение UUID: UUIDv5 и запись в виде контракта.
    /// UUID версии 5 (SHA-1, RFC 9562 §5.5) по пространству имён и имени в UTF-8.
    nonisolated static func version5(namespace: UUID, name: String) -> UUID {
        // Байты пространства имён в сетевом порядке, затем имя.
        var input = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        input.append(contentsOf: Array(name.utf8)) // Имя в UTF-8 после пространства имён.
        // Первые 16 байт SHA-1.
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // Версия 5.
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // Вариант RFC 4122/9562.
        return UUID(uuid: ( // UUID из 16 байт хеша.
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], // Байты 0–7.
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15] // Байты 8–15.
        )) // UUID из 16 байт.
    }

    /// Канонический вид контракта: нижний регистр (`Uuid` в `contract/openapi.yaml`).
    nonisolated var contractString: String {
        uuidString.lowercased() // `uuidString` Foundation — в верхнем регистре.
    }
}
