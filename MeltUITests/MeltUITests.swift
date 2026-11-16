import XCTest

final class MeltUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    func testStarterOrderAndPublish() {
        launch("empty")
        XCTAssertTrue(element("Polka-dot man keychain").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["model-preview"].exists)
        let orange = app.buttons["Tangerine"]
        orange.tap()
        XCTAssertTrue(orange.isSelected)
        capture("creator-keychain")

        app.buttons["Order"].tap()
        let checkout = app.buttons["Continue to checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 10))
        capture("order-review")
        checkout.tap()
        XCTAssertTrue(element("Order received").waitForExistence(timeout: 5))
        XCTAssertFalse(element("demo").exists)
        app.buttons["Done"].tap()

        let publish = app.buttons["Publish"]
        reveal(publish)
        publish.tap()
        let price = app.textFields["listing-price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        replace(price, with: "18.00")
        app.buttons["Publish"].tap()
        XCTAssertTrue(element("Your design is listed in Demo store.").waitForExistence(timeout: 5))
        capture("published-keychain")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(element("Polka-dot man keychain").waitForExistence(timeout: 5))
        capture("shop-keychain")
    }

    func testGenerateAndResumeAcrossTabs() {
        launch("empty")
        let prompt = app.descendants(matching: .any)["prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        reveal(prompt)
        replace(prompt, with: "A tiny rocket for my desk")
        app.buttons["generate"].tap()
        XCTAssertTrue(element("Generating model").waitForExistence(timeout: 5))
        capture("creator-generating")
        XCTAssertTrue(element("DRAFT").waitForExistence(timeout: 10))
        app.tabBars.buttons["My shelf"].tap()
        XCTAssertTrue(element("A tiny rocket for my desk").waitForExistence(timeout: 5))
        capture("shelf-design")
        app.tabBars.buttons["Create"].tap()
        XCTAssertTrue(element("A tiny rocket for my desk").waitForExistence(timeout: 5))
        XCTAssertFalse(element("Small idea").exists)
    }

    func testChallengesKeepBackingSecondary() {
        launch("demo")
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.buttons["Challenges"].waitForExistence(timeout: 10))
        capture("shop")
        app.buttons["Challenges"].tap()
        let fox = element("Fox desk buddy")
        reveal(fox)
        fox.tap()
        let backing = app.buttons["Back a design"]
        reveal(backing)
        capture("challenge")
        backing.tap()
        let stake = app.buttons["Back with 100 credits"]
        XCTAssertTrue(stake.waitForExistence(timeout: 5))
        stake.tap()
        XCTAssertTrue(element("You backed Fox desk buddy with 100 credits").waitForExistence(timeout: 5))
    }

    func testEmptyShelfAndSaveStarter() {
        launch("empty")
        app.tabBars.buttons["My shelf"].tap()
        XCTAssertTrue(element("No designs").waitForExistence(timeout: 10))
        capture("shelf-empty")
        app.tabBars.buttons["Create"].tap()
        let save = app.buttons["Save design"]
        reveal(save)
        save.tap()
        XCTAssertTrue(element("DRAFT").waitForExistence(timeout: 5))
        app.tabBars.buttons["My shelf"].tap()
        XCTAssertTrue(element("Polka-dot man keychain").waitForExistence(timeout: 5))
    }

    func testDisconnectedCreatorStillHasInteractiveStarter() {
        launch("error")
        XCTAssertTrue(element("Polka-dot man keychain").waitForExistence(timeout: 5))
        app.buttons["Tangerine"].tap()
        XCTAssertTrue(app.buttons["Tangerine"].isSelected)
        let retry = app.buttons["Try again"]
        reveal(retry)
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["generate"].isEnabled)
        capture("creator-offline")
        app.tabBars.buttons["My shelf"].tap()
        XCTAssertTrue(element("Couldn't connect").waitForExistence(timeout: 5))
    }

    func testLiveModel() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["MELT_LIVE_URL"], let modelName = environment["MELT_LIVE_MODEL"] else {
            throw XCTSkip("Set TEST_RUNNER_MELT_LIVE_URL and TEST_RUNNER_MELT_LIVE_MODEL to inspect an existing design")
        }
        app.launchArguments = ["-ConvexDeploymentURL", url]
        app.launch()
        app.tabBars.buttons["My shelf"].tap()
        let product = element(modelName)
        XCTAssertTrue(product.waitForExistence(timeout: 20))
        reveal(product)
        product.tap()
        XCTAssertTrue(app.buttons["Spin"].waitForExistence(timeout: 20))
        XCTAssertFalse(element("Preview unavailable").exists)
        capture("live-model")
    }

    func testBundledCatalogWithoutBackendOrDemoMode() {
        let keys = ["twisted-hex-vase", "capybara-planter", "ghost-night-light", "fox-desk-buddy",
                    "top-hat-duck", "hex-bins", "egg-cup"]
        for key in keys {
            app.launchArguments = ["-MeltInspectModel", "YES", "-MeltInspectCatalog", key,
                                   "-MeltScenario", "disabled", "-ConvexDeploymentURL", "http://127.0.0.1:1",
                                   "-MeltInspectReduceMotion", "YES"]
            app.launch()
            assertPreviewReady()
            XCTAssertTrue(app.buttons["Spin"].exists) // No automatic intro under Reduce Motion.
            capture("catalog-" + key)
            app.buttons["Tangerine"].tap()
            XCTAssertTrue(app.buttons["Tangerine"].isSelected)
            assertPreviewReady()
            app.buttons["Spin"].tap()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
            app.buttons["Pause"].tap()
            let preview = app.descendants(matching: .any)["model-preview"]
            preview.swipeLeft()
            assertPreviewReady()
            app.terminate()
        }
    }

    func testLiveCatalogShopAndChallenges() throws {
        guard let url = ProcessInfo.processInfo.environment["MELT_LIVE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_MELT_LIVE_URL to inspect the repaired development catalog")
        }
        app.launchArguments = ["-MeltScenario", "disabled", "-MeltInspectModel", "NO", "-ConvexDeploymentURL", url]
        app.launch()
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.buttons["Challenges"].waitForExistence(timeout: 20))
        for name in ["A polka-dot man keychain", "Egg cup", "Stackable hex bins", "Duck in a top hat", "Fox desk buddy",
                     "Ghost night light", "Sleepy capybara planter", "Twisted hex vase"] {
            let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            reveal(tile)
            XCTAssertTrue(tile.isHittable, name)
            capture("shop-" + name)
            tile.tap()
            assertPreviewReady()
            capture("detail-" + name)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        // Tab changes and scrolling must recreate compact scenes successfully.
        app.tabBars.buttons["Create"].tap()
        app.tabBars.buttons["Explore"].tap()
        for _ in 0..<5 { app.swipeDown() }
        app.buttons["Challenges"].tap()
        let challenge = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fox desk buddy")).firstMatch
        reveal(challenge)
        capture("catalog-challenge-cards")
        challenge.tap()
        XCTAssertTrue(element("Sales challenge").waitForExistence(timeout: 5))
        let previews = app.descendants(matching: .any).matching(identifier: "model-preview")
        XCTAssertGreaterThanOrEqual(previews.count, 2)
        for index in 0..<2 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'ready'"), object: previews.element(boundBy: index))
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        }
        capture("catalog-challenge-detail")
    }

    private func assertPreviewReady() {
        let preview = app.descendants(matching: .any)["model-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'ready'"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertFalse(element("Preview unavailable").exists)
    }

    private func launch(_ scenario: String) {
        app.launchArguments = ["-MeltScenario", scenario]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 10))
    }

    private func element(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        if let value = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText(text)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
