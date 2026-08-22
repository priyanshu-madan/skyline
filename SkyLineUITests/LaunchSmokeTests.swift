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
//  It must not assert WHICH surface it settles on. The first version waited for
//  the tab bar, which only appears when `DebugFlags.bypassAuthentication` is on
//  — so flipping that flag off for device testing failed a suite that had
//  nothing wrong with it. A launch test that breaks when a debug flag moves is
//  testing the flag.
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

        // Both legitimate destinations. Which one comes up depends on the auth
        // bypass flag and on whether this simulator has an iCloud account —
        // neither of which this test has an opinion about.
        let signIn = app.staticTexts["Welcome to SkyLine"]
        let shell = app.staticTexts["Trips"]

        // Poll for whichever arrives first. `XCTWaiter` cannot express "any
        // of these" — it waits for every expectation handed to it — so a plain
        // deadline loop is both shorter and honest about what it does.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline && !signIn.exists && !shell.exists {
            _ = signIn.waitForExistence(timeout: 1)
        }

        XCTAssertTrue(
            signIn.exists || shell.exists,
            "App reached neither the sign-in wall nor the main shell within 60s")

        XCTAssertEqual(app.state, .runningForeground, "App left the foreground during launch")
    }
}
