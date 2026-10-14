import XCTest

final class MoneyPlannerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Приложение запускается без сети и с временной БД и показывает RootView.
    @MainActor
    func testLaunchShowsRootViewWithoutNetwork() throws {
        let app = XCUIApplication.makeForUITesting()
        app.launch()

        XCTAssertTrue(app.navigationBars["Проверка запуска"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Хранилище готово"].exists)
        // В режиме UI-тестов сеть отключена: проверка сервера недоступна.
        XCTAssertTrue(app.staticTexts["Адрес сервера не настроен"].exists)
        XCTAssertFalse(app.buttons["launchCheck.checkServer"].isEnabled)
    }

    /// RootView отображается при максимальном размере Dynamic Type.
    @MainActor
    func testLaunchWithAccessibilityTextSize() throws {
        let app = XCUIApplication.makeForUITesting()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Хранилище готово"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Хранилище готово"].isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "RootView AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication.makeForUITesting().launch()
        }
    }
}

extension XCUIApplication {
    /// Запуск в режиме UI-тестов: временная БД, без сети, русская локаль.
    static func makeForUITesting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        return app
    }
}
