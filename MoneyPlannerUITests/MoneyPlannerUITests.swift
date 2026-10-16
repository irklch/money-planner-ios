// MoneyPlannerUITests.swift
// UI-тесты главного экрана и истории на изолированных fixtures: временная БД, без сети.

import XCTest

final class MoneyPlannerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Главный экран с расходами: итог, полоса, категории и история за период; сеть не нужна.
    @MainActor
    func testHomeShowsExpenses() throws {
        let app = XCUIApplication.makeForUITesting(fixture: "filled")
        app.launch()

        XCTAssertTrue(app.navigationBars["Обзор"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["home.total"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["home.distributionBar"].exists || app.descendants(matching: .any)["home.distributionBar"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "home.categoryRow").count, 4)
        XCTAssertTrue(app.staticTexts["История · \(Self.currentMonthName())"].exists)
        // Расход категории, которой нет на устройстве, виден в истории.
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "history.row").firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Главный экран — история")
    }

    /// Пустой период: состояние H9 вместо нулей; выбор другого периода показывает расходы.
    @MainActor
    func testEmptyPeriod() throws {
        let app = XCUIApplication.makeForUITesting(fixture: "previousMonthOnly")
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["empty.state"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["home.total"].exists)
        attachScreenshot(app, name: "Пустой период")

        app.buttons["empty.choosePeriod"].tap()
        app.buttons["period.option.previousMonth"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["home.total"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["empty.state"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "home.categoryRow").count, 3)
    }

    /// Смена периода обновляет итог и историю.
    @MainActor
    func testPeriodChangeUpdatesTotalAndHistory() throws {
        let app = XCUIApplication.makeForUITesting(fixture: "filled")
        app.launch()

        let total = app.staticTexts["home.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 30))
        let monthTotal = total.label

        app.buttons["period.menu"].tap()
        XCTAssertTrue(app.buttons["period.option.last90Days"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Выбор периода")
        app.buttons["period.option.last90Days"].tap()

        XCTAssertTrue(app.staticTexts["История · 90 дней"].waitForExistence(timeout: 10))
        XCTAssertNotEqual(total.label, monthTotal)
        XCTAssertTrue(app.buttons["period.menu"].label.contains("90 дней"))
    }

    /// Список категорий раскрывается и сворачивается на месте, без перехода на другой экран.
    @MainActor
    func testCategoriesExpandInPlace() throws {
        let app = XCUIApplication.makeForUITesting(fixture: "filled")
        app.launch()

        let toggle = app.buttons["home.categories.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(identifier: "home.categoryRow").count, 4)

        toggle.tap()
        XCTAssertGreaterThan(app.buttons.matching(identifier: "home.categoryRow").count, 4)
        XCTAssertTrue(app.navigationBars["Обзор"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["category"].exists)
        attachScreenshot(app, name: "Категории раскрыты")

        app.buttons["home.categories.toggle"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "home.categoryRow").count, 4)
    }

    /// Переход к истории категории сохраняет выбранный период, возврат его не сбрасывает.
    @MainActor
    func testCategoryHistoryKeepsPeriod() throws {
        let app = XCUIApplication.makeForUITesting(fixture: "filled")
        app.launch()

        XCTAssertTrue(app.buttons["period.menu"].waitForExistence(timeout: 30))
        app.buttons["period.menu"].tap()
        app.buttons["period.option.last30Days"].tap()
        XCTAssertTrue(app.staticTexts["История · 30 дней"].waitForExistence(timeout: 10))

        let firstCategory = app.buttons.matching(identifier: "home.categoryRow").firstMatch
        firstCategory.tap()

        XCTAssertTrue(app.staticTexts["category.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["category.total"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["period.menu"].label.contains("30 дней"))
        XCTAssertTrue(app.staticTexts["История · 30 дней"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "history.row").firstMatch.exists)
        attachScreenshot(app, name: "История категории")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["home.total"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["period.menu"].label.contains("30 дней"))
    }

    /// Главный экран отображается при максимальном размере Dynamic Type.
    @MainActor
    func testLargeDynamicType() throws {
        let app = XCUIApplication.makeForUITesting(fixture: "filled")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["home.total"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["period.menu"].isHittable)
        attachScreenshot(app, name: "Главный экран AX5")
        app.swipeUp()
        attachScreenshot(app, name: "Главный экран AX5 — прокрутка")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication.makeForUITesting().launch()
        }
    }

    /// Месяц «сегодня» строчными, как в заголовке истории.
    private static func currentMonthName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: .now)
    }
}

extension XCTestCase {
    /// Скриншот в результатах теста.
    @MainActor
    func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIApplication {
    /// Запуск в режиме UI-тестов: временная БД, без сети, русская локаль и при необходимости fixture.
    static func makeForUITesting(fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        if let fixture { app.launchArguments += ["--ui-fixture", fixture] }
        return app
    }
}
