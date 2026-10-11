import Foundation
import Testing
@testable import MoneyPlanner

@Suite("AppConfiguration")
struct AppConfigurationTests {
    @Test(arguments: [
        ("http://localhost:8000", "http://localhost:8000"),
        ("  https://api.example.test/base  ", "https://api.example.test/base"),
    ])
    func validBaseURL(raw: String, expected: String) {
        #expect(AppConfiguration.parseBaseURL(raw) == URL(string: expected))
    }

    @Test(arguments: [nil, "", "   ", "localhost:8000", "ftp://example.test", "https://", "https://x.test?a=1", "$(MP_API_BASE_URL)"])
    func invalidBaseURLDisablesNetwork(raw: String?) {
        #expect(AppConfiguration.parseBaseURL(raw) == nil)
    }

    @Test func readsInfoDictionary() {
        let configuration = AppConfiguration(infoDictionary: [
            AppConfiguration.apiBaseURLKey: "https://api.example.test",
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "34",
        ])

        #expect(configuration == AppConfiguration(apiBaseURL: URL(string: "https://api.example.test"), appVersion: "1.2", buildNumber: "34"))
    }
}

@MainActor
@Suite("Design system")
struct DesignSystemTests {
    @Test func categoryPaletteMatchesBackendPaletteSize() {
        // backend: app/core/config.py, category_palette_size = 12
        #expect(CategoryPalette.colors.count == 12)
    }

    @Test(arguments: [(0, 0), (11, 11), (12, 0), (25, 1), (-1, 11)])
    func categoryPaletteWrapsIndex(index: Int, expected: Int) {
        #expect(CategoryPalette.color(at: index) == CategoryPalette.colors[expected])
    }
}
