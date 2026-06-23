import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    private var outputDirectory: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"]
            ?? "/tmp/nucleus-app-store-screenshots"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-screenshotMode")
        app.launchEnvironment["SCREENSHOT_OUTPUT_DIR"] = outputDirectory
        app.launch()

        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for title in ["Allow While Using App", "Allow Once", "OK", "Not Now"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        XCTAssertTrue(waitForMainInterface(app: app, timeout: 60))
        sleep(1)
        saveScreenshot(named: "01-dashboard", app: app)

        navigate(to: "Settings", app: app)
        sleep(2)
        saveScreenshot(named: "06-settings-security", app: app)
        app.swipeUp(velocity: .slow)
        sleep(1)
        saveScreenshot(named: "07-settings-notifications", app: app)

        navigate(to: "Notes", app: app)
        sleep(1)
        saveScreenshot(named: "02-notes-list", app: app)
        if app.buttons["notes.add"].waitForExistence(timeout: 5) {
            app.buttons["notes.add"].tap()
            sleep(1)
            let editor = app.textViews.firstMatch
            if editor.waitForExistence(timeout: 3) {
                editor.tap()
                editor.typeText("# Weekly plan\n\n- Review bills\n- Update passwords\n- Sync with computer")
            }
            saveScreenshot(named: "03-notes-detail", app: app)
            goBack(app: app)
        }

        navigate(to: "Passwords", app: app)
        sleep(1)
        if app.buttons["passwords.add"].waitForExistence(timeout: 5) {
            app.buttons["passwords.add"].tap()
            sleep(1)
            fillPasswordForm(app: app)
            saveScreenshot(named: "04-passwords-detail", app: app)
            goBack(app: app)
        } else {
            saveScreenshot(named: "04-passwords-list", app: app)
        }

        navigate(to: "Bills", app: app)
        sleep(1)
        saveScreenshot(named: "05-bills", app: app)
    }

    private func clearText(on element: XCUIElement) {
        element.tap()
        guard let stringValue = element.value as? String, !stringValue.isEmpty else { return }
        let deleteString = String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: stringValue.count
        )
        element.typeText(deleteString)
    }

    private func fillPasswordForm(app: XCUIApplication) {
        let title = app.textFields["Title"]
        if title.waitForExistence(timeout: 3) {
            title.tap()
            clearText(on: title)
            title.typeText("Example Bank")
        }

        let url = app.textFields["URL"]
        if url.exists {
            url.tap()
            url.typeText("https://bank.example.com")
        }

        let username = app.textFields["Username"]
        if username.exists {
            username.tap()
            username.typeText("demo.user")
        }

        let email = app.textFields["Email"]
        if email.exists {
            email.tap()
            email.typeText("demo@example.com")
        }

        let password = app.secureTextFields["Password"]
        if password.exists {
            password.tap()
            password.typeText("demo-password-123")
        }
    }

    private func waitForMainInterface(app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.tabBars.firstMatch.exists { return true }
            if app.buttons["Dashboard"].exists { return true }
            if app.staticTexts["Dashboard"].exists { return true }
            if app.navigationBars["Nucleus"].exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func navigate(to tab: String, app: XCUIApplication) {
        if app.tabBars.firstMatch.exists {
            let button = app.tabBars.buttons[tab]
            if button.exists {
                button.tap()
            } else {
                app.tabBars.buttons.element(boundBy: tabIndex(for: tab)).tap()
            }
            return
        }

        if app.buttons[tab].exists {
            app.buttons[tab].tap()
            return
        }

        app.staticTexts[tab].firstMatch.tap()
    }

    private func tabIndex(for tab: String) -> Int {
        switch tab {
        case "Dashboard": return 0
        case "Notes": return 1
        case "Passwords": return 2
        case "Bills": return 3
        case "Settings": return 4
        default: return 0
        }
    }

    private func goBack(app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists {
            back.tap()
        }
    }

    private func saveScreenshot(named name: String, app: XCUIApplication) {
        XCTAssertTrue(app.state == .runningForeground, "App must be running before screenshot \(name)")

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let path = (outputDirectory as NSString).appendingPathComponent("\(name).png")
        let image = screenshot.image
        guard let data = image.pngData() else {
            XCTFail("Could not encode screenshot \(name)")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            XCTFail("Could not write screenshot \(name): \(error)")
        }
    }
}
