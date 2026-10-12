import XCTest

final class DynamicIslandUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // App launches and stays alive without crashing.
    func testAppLaunchesWithoutCrashing() throws {
        let isRunning = app.wait(for: .runningForeground, timeout: 10.0)
            || app.wait(for: .runningBackground, timeout: 10.0)
        XCTAssertTrue(isRunning, "App should be running after launch.")
        XCTAssertNotEqual(app.state, .notRunning, "App should not have terminated.")
    }

    // The notch panel is present and exposed to accessibility.
    func testNotchExpansion() throws {
        let notch = app.descendants(matching: .any)["EaveNotch"]
        XCTAssertTrue(notch.waitForExistence(timeout: 15.0), "The Eave notch should be visible.")
    }

    func testCodexDetailExpandsWindow() throws {
        app.terminate()
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-reopenTab", "system-llmUsage"
        ]
        app.launch()
        let notch = app.descendants(matching: .any)["EaveNotch"].firstMatch
        XCTAssertTrue(notch.waitForExistence(timeout: 15))
        notch.click()
        // Hover can open the panel before the click applies the preferred tab.
        if !app.buttons["Open Codex details"].exists {
            let usage = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'chart'")).firstMatch
            guard usage.exists else { throw XCTSkip("Enable the Usage tab and Codex provider before this UI check.") }
            usage.click()
        }
        let details = app.buttons["Open Codex details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        let panel = app.dialogs.firstMatch
        let compactHeight = panel.frame.height
        details.click()
        let expanded = NSPredicate { _, _ in panel.frame.height > compactHeight + 200 }
        expectation(for: expanded, evaluatedWith: panel)
        waitForExpectations(timeout: 5)
        app.buttons["Back to usage"].click()
        let collapsed = NSPredicate { _, _ in abs(panel.frame.height - compactHeight) < 2 }
        expectation(for: collapsed, evaluatedWith: panel)
        waitForExpectations(timeout: 5)
    }
}
