//
//  LaunchSmokeTests.swift
//  SkyLineUITests
//
//  The UI test target previously had no sources at all, which made its runner
//  crash on bootstrap and failed the whole `xcodebuild test` action even when
//  every unit test passed. One real test is both the fix and a genuine check:
//  the app has a WebView-hosted globe and a CloudKit sync on the launch path,
//  so "it launches and settles" is worth asserting.
//

import XCTest

final class LaunchSmokeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndPresentsItsShell() {
        let app = XCUIApplication()
        app.launch()

        // The DEBUG auth bypass means we land in the app shell rather than the
        // sign-in wall. The tab bar is the first durable thing to appear; the
        // globe behind it loads asynchronously in a WebView.
        let trips = app.staticTexts["Trips"]
        XCTAssertTrue(
            trips.waitForExistence(timeout: 60),
            "App did not reach its main shell within 60s of launch")

        XCTAssertEqual(app.state, .runningForeground, "App left the foreground during launch")
    }
}
