import XCTest

final class MeltUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testArenaCreateAndLibraryFlow() {
        app.launchArguments = ["-MeltScenario", "demo"]
        app.launch()

        let foxDuel = element(containing: "Fox desk buddy")
        XCTAssertTrue(foxDuel.waitForExistence(timeout: 10))
        capture("arena")

        foxDuel.tap()
        let stakeButton = app.buttons["Stake 100 credits"]
        XCTAssertTrue(stakeButton.waitForExistence(timeout: 5))
        stakeButton.tap()
        XCTAssertTrue(element(containing: "You backed Fox desk buddy with 100 credits").waitForExistence(timeout: 5))
        capture("duel-staked")

        element(containing: "Duck in a top hat").tap()
        XCTAssertTrue(element(containing: "A duck in a top hat for my desk").waitForExistence(timeout: 5))
        sleep(2)
        capture("product-preview")

        app.tabBars.buttons["Create"].tap()
        let prompt = app.descendants(matching: .any)["prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("A tiny rocket for my desk")
        app.buttons["Generate model"].tap()
        XCTAssertTrue(element(containing: "Generating the model").waitForExistence(timeout: 5))
        capture("create-generating")
        XCTAssertTrue(element(containing: "Draft · $15.00").waitForExistence(timeout: 10))

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(element(containing: "A tiny rocket for my desk").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "1,150").exists)
        capture("library")
    }

    func testEmptyLibrary() {
        app.launchArguments = ["-MeltScenario", "empty"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(element(containing: "No designs yet").waitForExistence(timeout: 10))
        capture("library-empty")
    }

    func testLoadFailure() {
        app.launchArguments = ["-MeltScenario", "error"]
        app.launch()
        XCTAssertTrue(element(containing: "Can't load Melt").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].exists)
        capture("load-error")
    }

    func testLiveBackend() throws {
        guard let url = ProcessInfo.processInfo.environment["MELT_LIVE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_MELT_LIVE_URL to a freshly reset Convex deployment to run this test")
        }
        app.launchArguments = ["-ConvexDeploymentURL", url]
        app.launch()

        let hexDuel = element(containing: "Stackable hex bins")
        XCTAssertTrue(hexDuel.waitForExistence(timeout: 20))
        capture("live-arena")

        hexDuel.tap()
        let stakeButton = app.buttons["Stake 100 credits"]
        XCTAssertTrue(stakeButton.waitForExistence(timeout: 5))
        stakeButton.tap()
        XCTAssertTrue(element(containing: "You backed Stackable hex bins with 100 credits").waitForExistence(timeout: 10))
        capture("live-duel-staked")

        app.tabBars.buttons["Create"].tap()
        let prompt = app.descendants(matching: .any)["prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("A tiny rocket for my desk")
        app.buttons["Generate model"].tap()
        XCTAssertTrue(element(containing: "Generating the model").waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "Draft · $15.00").waitForExistence(timeout: 15))

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(element(containing: "1,150").waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "A tiny rocket for my desk").exists)
        capture("live-library")
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
