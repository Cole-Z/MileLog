import XCTest

@MainActor final class ReviewFlowTests: XCTestCase {
    func testIncompleteTripCanBeRepairedFromReportsAndShared() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Start my log"].waitForExistence(timeout: 3) {
            app.buttons["Start my log"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Trips"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Reports"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Startup must not request location")
        app.buttons["Add trip"].tap()
        let name = "Test destination \(UUID().uuidString.prefix(6))"
        let destination = input("Destination / business location", in: app)
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap(); destination.typeText(name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Trip saved"].waitForExistence(timeout: 5))
        app.buttons["Dismiss confirmation"].tap()
        let reviewToggle = app.switches["Needs review"]
        if !reviewToggle.isHittable { app.swipeUp() }
        XCTAssertTrue(reviewToggle.exists)
        reviewToggle.tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        snapshot(app, "Needs-review-filter")
        app.tabBars.buttons["Reports"].tap()
        let reviewLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Needs review ·")).firstMatch
        for _ in 0..<3 where !reviewLink.isHittable { app.swipeUp() }
        XCTAssertTrue(reviewLink.exists)
        reviewLink.tap()
        app.buttons.containing(.staticText, identifier: name).firstMatch.tap()
        let start = input("Start location", in: app)
        start.tap(); start.typeText("Office")
        app.buttons["Done"].tap()
        let miles = app.textFields["tripMiles"]
        for _ in 0..<3 where !miles.isHittable { app.swipeUp() }
        miles.tap(); miles.typeText("2.5")
        app.buttons["Done"].tap()
        let purpose = input("What was the business purpose?", in: app)
        for _ in 0..<3 where !purpose.isHittable { app.swipeUp() }
        purpose.tap(); purpose.typeText("Client meeting")
        app.buttons["Save"].tap()
        XCTAssertFalse(app.staticTexts[name].waitForExistence(timeout: 2), "Repaired trip must leave the review list")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let csv = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "as CSV")).firstMatch
        for _ in 0..<6 where !csv.isHittable { app.swipeUp() }
        XCTAssertTrue(csv.isHittable)
        csv.tap()
        dismissShare(app, attachment: "CSV-share-sheet")
        app.buttons["Share printable PDF"].tap()
        dismissShare(app, attachment: "PDF-share-sheet")
        XCTAssertEqual(app.alerts.count, 0)
        app.tabBars.buttons["Trips"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Trips"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0)
        snapshot(app, "Returning-user-trips")
    }

    private func input(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: label)
            .matching(NSPredicate(format: "elementType == %d OR elementType == %d", Int(XCUIElement.ElementType.textField.rawValue), Int(XCUIElement.ElementType.textView.rawValue))).firstMatch
    }
    private func dismissShare(_ app: XCUIApplication, attachment: String) {
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        snapshot(app, attachment)
        close.tap()
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
