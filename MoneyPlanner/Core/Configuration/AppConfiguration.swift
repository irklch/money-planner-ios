// AppConfiguration.swift
// Конфигурация окружения из Info.plist и определение режима запуска процесса.

// Foundation нужен для URL, Bundle и ProcessInfo.
import Foundation

/// Конфигурация окружения, прочитанная из Info.plist.
///
/// Значения задаются в `Configuration/*.xcconfig` и подставляются в `Configuration/MoneyPlanner-Info.plist`.
nonisolated struct AppConfiguration: Sendable, Equatable {
    /// Ключ Info.plist, в который xcconfig подставляет base URL API.
    static let apiBaseURLKey = "MPAPIBaseURL"

    /// Origin бэкенда без `/v1`. `nil`, если адрес не настроен: тогда сетевые сервисы отключены.
    let apiBaseURL: URL?
    /// Версия приложения (`CFBundleShortVersionString`).
    let appVersion: String
    /// Номер сборки (`CFBundleVersion`).
    let buildNumber: String

    /// Создаёт конфигурацию из готовых значений (previews и тесты).
    init(apiBaseURL: URL?, appVersion: String, buildNumber: String) {
        self.apiBaseURL = apiBaseURL // Сохраняем base URL как есть.
        self.appVersion = appVersion // Сохраняем версию приложения.
        self.buildNumber = buildNumber // Сохраняем номер сборки.
    }

    /// Создаёт конфигурацию из словаря Info.plist.
    init(infoDictionary: [String: Any]) {
        self.apiBaseURL = Self.parseBaseURL(infoDictionary[Self.apiBaseURLKey] as? String) // Проверяем и разбираем адрес API.
        self.appVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? "" // Версия приложения или пустая строка.
        self.buildNumber = infoDictionary["CFBundleVersion"] as? String ?? "" // Номер сборки или пустая строка.
    }

    /// Конфигурация текущего бандла приложения.
    static func current(bundle: Bundle = .main) -> AppConfiguration {
        AppConfiguration(infoDictionary: bundle.infoDictionary ?? [:]) // Читаем Info.plist; без него — пустая конфигурация.
    }

    /// Принимает только абсолютный http(s)-адрес с хостом, без query и fragment.
    static func parseBaseURL(_ rawValue: String?) -> URL? {
        guard
            let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), // Убираем пробелы по краям.
            !trimmed.isEmpty, // Пустое значение — адрес не настроен.
            let components = URLComponents(string: trimmed), // Разбираем строку как URL.
            let scheme = components.scheme?.lowercased(), // Схема без учёта регистра.
            scheme == "https" || scheme == "http", // Разрешены только http и https.
            let host = components.host, !host.isEmpty, // Нужен непустой хост.
            components.query == nil, components.fragment == nil // Query и fragment в base URL не допускаются.
        else { return nil } // Любое нарушение — сеть отключена.
        return components.url // Корректный base URL.
    }
}

/// Режим запуска процесса. Определяет, можно ли обращаться к пользовательской БД и сети.
nonisolated enum LaunchMode: Sendable, Equatable {
    /// Обычный запуск приложения.
    case app
    /// UI-тесты: временное хранилище, без сети.
    case uiTesting
    /// Процесс-хост unit-тестов: временное хранилище, без сети.
    case unitTesting
    /// Xcode Previews: временное хранилище, без сети.
    case preview

    /// Аргумент запуска, который передают UI-тесты.
    static let uiTestingArgument = "--ui-testing"

    /// Определяет режим по аргументам и переменным окружения процесса.
    static func detect(processInfo: ProcessInfo = .processInfo) -> LaunchMode {
        let environment = processInfo.environment // Переменные окружения, которые выставляет Xcode.
        if processInfo.arguments.contains(uiTestingArgument) { return .uiTesting } // Аргумент передают UI-тесты.
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return .preview } // Переменная Xcode Previews.
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil { // Переменные XCTest в процессе-хосте.
            return .unitTesting // Приложение запущено как хост unit-тестов.
        }
        return .app // Иначе — обычный запуск.
    }

    /// Использовать постоянное пользовательское хранилище.
    var usesPersistentStore: Bool { self == .app } // Только обычный запуск работает с файлом БД пользователя.

    /// Разрешены реальные сетевые запросы.
    var allowsNetwork: Bool { self == .app } // Previews и тесты не ходят в сеть.
}
