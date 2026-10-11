import XCTest

final class MindNativeUITests: XCTestCase {
    func testWelcomeCreatesIdeaAndOpensInspector() {
        let app = launchNewDocument()

        let newIdea = app.buttons["New idea"].firstMatch
        XCTAssertTrue(newIdea.waitForExistence(timeout: 5))
        newIdea.click()
        app.typeKey(.escape, modifierFlags: [])

        app.buttons["Inspector"].click()
        let inspector = app.descendants(matching: .any)["idea-inspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))

        let title = app.textFields["inspector-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        let idea = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "idea-")
        ).firstMatch
        XCTAssertTrue(idea.exists)
    }

    func testPresentationCanStartAndExit() {
        let app = launchNewDocument()

        let newIdea = app.buttons["New idea"].firstMatch
        XCTAssertTrue(newIdea.waitForExistence(timeout: 5))
        newIdea.click()
        app.typeKey(.escape, modifierFlags: [])

        let idea = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "idea-")
        ).firstMatch
        XCTAssertTrue(idea.waitForExistence(timeout: 3))
        idea.rightClick()
        app.menuItems["Present from Here"].click()
        let presentation = app.descendants(matching: .any)["presentation-overlay"].firstMatch
        XCTAssertTrue(presentation.waitForExistence(timeout: 3))

        app.buttons["Done"].click()
        XCTAssertFalse(presentation.waitForExistence(timeout: 1))
    }

    func testDoubleClickEmptyCanvasCreatesIdea() {
        let app = launchNewDocument()

        let canvas = app.descendants(matching: .any)["mind-map-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let idea = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "idea-")
        ).firstMatch
        XCTAssertFalse(idea.exists)

        canvas.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.22)
        ).doubleClick()

        XCTAssertTrue(idea.waitForExistence(timeout: 3))
    }

    private func launchNewDocument() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let documentChooserButton = app.buttons["NewDocumentButton"]
        if documentChooserButton.waitForExistence(timeout: 3) {
            documentChooserButton.click()
        } else {
            let newDocument = app.buttons["New Document"]
            if newDocument.waitForExistence(timeout: 1) {
                newDocument.click()
            }
        }
        return app
    }
}
