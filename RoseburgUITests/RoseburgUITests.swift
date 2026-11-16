//
//  RoseburgUITests.swift
//  RoseburgUITests
//
//  Walks through the main screens with sample data and saves a screenshot of each.
//  The screenshots are attached to the test result, so they can be exported from the .xcresult.
//

import XCTest

final class RoseburgUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingDemo"]
        app.launch()

        // 1. The grocery list, sorted by aisle, with a checked item.
        XCTAssertTrue(app.navigationBars["ListToShop"].waitForExistence(timeout: 15))
        attach(app, name: "1-grocery-list")

        // 2. The Recipes sheet for an item.
        let recipesButton = app.buttons["Recipes"].firstMatch
        XCTAssertTrue(recipesButton.waitForExistence(timeout: 5))
        recipesButton.tap()
        XCTAssertTrue(app.navigationBars["Broccoli rabe"].waitForExistence(timeout: 5))
        attach(app, name: "2-item-recipes")
        app.buttons["Done"].tap()

        // 3. A recipe's own ingredient lines.
        let recipeLink = scrollToElement(app.staticTexts["Chicken Enchiladas"], in: app)
        recipeLink.tap()
        XCTAssertTrue(app.navigationBars["Chicken Enchiladas"].waitForExistence(timeout: 5))
        attach(app, name: "3-recipe-ingredients")

        // 4. The same recipe's steps, with each line as written on the recipe.
        app.swipeUp()
        attach(app, name: "4-recipe-steps")
    }

    /// Scrolls until the element can be tapped, or gives up after a few swipes.
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        return element
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
