import XCTest

/// App Store screenshots from the review demo (`DemoMode`, "Try Demo" on a fresh install's lock
/// screen): example codes and a simulated sign-in request, in Busnes Light and Busnes Dark. Not a
/// correctness test. Skipped unless `KYAUTH_SCREENSHOTS=1`; `scripts/capture-screenshots.sh` sets it
/// and exports the attachments from the result bundle.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KYAUTH_SCREENSHOTS"] == "1",
            "Set KYAUTH_SCREENSHOTS=1 (scripts/capture-screenshots.sh) to capture."
        )
        continueAfterFailure = false
    }

    /// One launch per appearance. `-appearance <value>` sets the app's own setting
    /// (`Appearance.defaultsKey`) for that launch only; `XCUIDevice.appearance` did not reach new
    /// iOS 27 simulators.
    @MainActor
    func testCaptureDemo() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-appearance", appearance]
            app.launch()
            let tryDemo = app.buttons["Try Demo"]
            XCTAssertTrue(tryDemo.waitForExistence(timeout: 10), "Try Demo is shown only on an unpaired install")
            tryDemo.tap()
            try captureRequestThenCodes(app, suffix: appearance)
            app.terminate()
        }
    }

    /// Demo requests arrive within 5 s of the demo starting and 15 s after the last answer, so the
    /// request is captured first; denying it leaves 15 s of plain codes once its toast has gone.
    /// Both shots fall in one 30 s code period with at least 15 s left, before the codes turn red.
    private func captureRequestThenCodes(_ app: XCUIApplication, suffix: String) throws {
        let deny = app.buttons["Deny"]
        XCTAssertTrue(deny.waitForExistence(timeout: 25), "No demo sign-in request arrived")
        settle(3) // the "request received" toast lasts 2.5 s
        let left = 30 - Int(Date().timeIntervalSince1970) % 30
        if left < 20 { settle(TimeInterval(left) + 1) } // the request itself lasts 60 s
        capture("02-request-\(suffix)")
        // On iPad the first tap is sometimes dropped; a second one is harmless.
        deny.tap()
        if !deny.waitForNonExistence(timeout: 3) { deny.tap() }
        XCTAssertTrue(deny.waitForNonExistence(timeout: 3), "The request did not clear")
        settle(3) // the "Sign-in denied" toast
        capture("01-codes-\(suffix)")
    }

    /// Every whole simulator screen, so the listing keeps its status bar. A device with more than
    /// one display (iPhone Duo) gets one image per display, named by its pixel size.
    private func capture(_ name: String) {
        let screens = XCUIScreen.screens
        for screen in screens {
            let shot = screen.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            if screens.count == 1 {
                attachment.name = name
            } else {
                let size = shot.image.size, scale = shot.image.scale
                attachment.name = "\(name)-\(Int(size.width * scale))x\(Int(size.height * scale))"
            }
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Plain sleep on purpose: only SwiftUI animations and toasts are waited out.
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
