import Foundation

/// Конфигурация окружения, прочитанная из Info.plist.
///
/// Значения задаются в `Configuration/*.xcconfig` и подставляются в `Configuration/MoneyPlanner-Info.plist`.
nonisolated struct AppConfiguration: Sendable, Equatable {
    static let apiBaseURLKey = "MPAPIBaseURL"

    /// Origin бэкенда без `/v1`. `nil`, если адрес не настроен: тогда сетевые сервисы отключены.
    let apiBaseURL: URL?
    /// `CFBundleShortVersionString`.
    let appVersion: String
    /// `CFBundleVersion`.
    let buildNumber: String

    init(apiBaseURL: URL?, appVersion: String, buildNumber: String) {
        self.apiBaseURL = apiBaseURL
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    init(infoDictionary: [String: Any]) {
        self.apiBaseURL = Self.parseBaseURL(infoDictionary[Self.apiBaseURLKey] as? String)
        self.appVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? ""
        self.buildNumber = infoDictionary["CFBundleVersion"] as? String ?? ""
    }

    static func current(bundle: Bundle = .main) -> AppConfiguration {
        AppConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
    }

    /// Принимает только абсолютный http(s)-адрес с хостом, без query и fragment.
    static func parseBaseURL(_ rawValue: String?) -> URL? {
        guard
            let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty,
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host, !host.isEmpty,
            components.query == nil, components.fragment == nil
        else { return nil }
        return components.url
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

    static func detect(processInfo: ProcessInfo = .processInfo) -> LaunchMode {
        let environment = processInfo.environment
        if processInfo.arguments.contains(uiTestingArgument) { return .uiTesting }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return .preview }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return .unitTesting
        }
        return .app
    }

    /// Использовать постоянное пользовательское хранилище.
    var usesPersistentStore: Bool { self == .app }

    /// Разрешены реальные сетевые запросы.
    var allowsNetwork: Bool { self == .app }
}
