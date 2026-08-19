//
//  HarnessTests.swift
//  SkyLineTests
//
//  Proves the test target is wired up and can see the app module. If this
//  fails, nothing else in the suite is trustworthy.
//

import Testing
@testable import SkyLine

@Suite("Test harness")
struct HarnessTests {

    @Test("The test target can reach app types")
    func canSeeAppModule() {
        // Verdict is the app's core vocabulary; if the module is linked, this
        // resolves. Compilation is the real assertion here.
        let theme = AppTheme.dark
        #expect(theme.colors.primary != theme.colors.background)
    }
}
