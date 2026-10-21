import XCTest

@MainActor
final class IsloraScreenshotTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.isloragames.islora")
    var activePlot = 0
    var topRows: [Int: Int] = [:]

    func testCameraZoomPanAndFit() throws {
        continueAfterFailure = false
        topRows = [0: 2, 1: 1, 2: 2, 3: 2, 4: 0]
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "1"
        app.launchEnvironment["ISLORA_TEST_SAVE_NAME"] = "islora-marketing-20261020.json"
        app.launch()
        if app.buttons["Collect"].waitForExistence(timeout: 3) { app.buttons["Collect"].tap() }
        openPlot(2)
        settle()
        let zoom = app.staticTexts["camera-zoom-level"]
        let initial = zoom.label
        app.buttons["camera-zoom-in"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotEqual(zoom.label, initial)
        app.buttons["camera-zoom-out"].tap()
        app.buttons["camera-fit"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(zoom.label, initial)
        let from = grid(0, 1)
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 45, dy: -35)))
        XCTAssertFalse(app.alerts["Remove Module?"].exists)
        app.buttons["camera-fit"].tap()
        app.pinch(withScale: 1.3, velocity: 1)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotEqual(zoom.label, initial)
        XCTAssertFalse(app.alerts["Remove Module?"].exists)
        app.buttons["camera-fit"].tap()
        settle()
        capture("camera_data_center_fit")
    }

    func testLivingCityAnimationsAtNormalSpeed() throws {
        continueAfterFailure = false
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "1"
        app.launchEnvironment["ISLORA_TEST_SAVE_NAME"] = "islora-motion-\(UUID()).json"
        app.launch()
        XCTAssertTrue(app.buttons["Claim"].waitForExistence(timeout: 10))
        app.buttons["Claim"].tap()
        openPlot(0)
        place("foundation_basic", x: -2, y: 0)
        Thread.sleep(forTimeInterval: 2)
        capture("construction_worker")
        Thread.sleep(forTimeInterval: 7)
        place("farm_field", x: -2, y: 1)
        Thread.sleep(forTimeInterval: 2)
        capture("field_construction")
        Thread.sleep(forTimeInterval: 9)
        grid(-2, 1).tap()
        XCTAssertTrue(app.alerts.buttons["Remove Module"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        app.buttons["Contracts"].tap()
        XCTAssertTrue(app.buttons["Claim Journey Reward"].waitForExistence(timeout: 5))
        app.buttons["Claim Journey Reward"].tap()
        capture("journey_reward")
        XCTAssertTrue(app.staticTexts["Catch the Sun"].exists)
    }

    func testUpdatedMarketingScreenshots() throws {
        topRows = [0: 2, 1: 1, 2: 2, 3: 2, 4: 0]
        continueAfterFailure = false
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "60000"
        app.launchEnvironment["ISLORA_TEST_SAVE_NAME"] = "islora-marketing-20261020.json"
        app.launch()
        if app.buttons["Collect"].waitForExistence(timeout: 3) { app.buttons["Collect"].tap() }
        XCTAssertFalse(app.buttons["Claim"].exists, "Requires the already-played marketing city")
        app.buttons["Contracts"].tap()
        let foodOrder = app.buttons["contract-action-0"]
        for _ in 0..<8 {
            if foodOrder.isHittable { break }
            app.swipeUp()
        }
        // Play the new board with actual deliveries; legacy orders remain intact.
        for _ in 0..<3 {
            if foodOrder.label == "Accept" { foodOrder.tap() }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Deliver'"), object: foodOrder)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            foodOrder.tap()
        }
        for _ in 0..<5 { app.swipeDown() }
        for _ in 0..<12 {
            if !app.buttons["Claim Journey Reward"].exists { break }
            app.buttons["Claim Journey Reward"].tap()
        }
        dismissSheet(title: "Contracts")
        app.terminate()
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "1"
        app.launch()
        if app.buttons["Collect"].waitForExistence(timeout: 2) { app.buttons["Collect"].tap() }
        panToPlot(0)
        settle()
        capture("01_overview")
        openPlot(0)
        settle()
        capture("02_farm_construction")
        app.buttons["Done"].tap()
        app.buttons["Contracts"].tap()
        for _ in 0..<8 {
            if foodOrder.isHittable { break }
            app.swipeUp()
        }
        foodOrder.tap()
        settle()
        capture("03_contracts")
        dismissSheet(title: "Contracts")
        app.buttons["Profile"].tap()
        settle()
        capture("04_profile")
        dismissSheet(title: "Profile")
        app.buttons["Codex"].tap()
        settle()
        capture("05_codex")
        dismissSheet(title: "Codex")
        app.buttons["Project"].tap()
        settle()
        capture("06_world_project")
        dismissSheet(title: "World Project")
        openPlot(1)
        settle()
        capture("07_power_plant")
        app.buttons["Done"].tap()
        openPlot(2)
        settle()
        capture("08_data_center")
        app.buttons["Done"].tap()
        openPlot(4)
        if app.buttons["Farm"].exists { app.buttons["Farm"].tap() }
        XCTAssertTrue(app.buttons["Coastal Harvest"].waitForExistence(timeout: 5))
        capture("09_blueprint_picker")
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        settle()
        capture("10_settings")
    }

    func testJourneyAndVariedBoard() throws {
        continueAfterFailure = false
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "60000"
        app.launchEnvironment["ISLORA_TEST_SAVE_NAME"] = "islora-variety-ui-\(UUID()).json"
        app.launch()
        XCTAssertTrue(app.buttons["Claim"].waitForExistence(timeout: 10))
        app.buttons["Claim"].tap()
        openPlot(0)
        place("foundation_basic", x: -2, y: 0)
        place("farm_field", x: -2, y: 1)
        app.buttons["Done"].tap()
        app.buttons["Contracts"].tap()
        let claim = app.buttons["Claim Journey Reward"]
        XCTAssertTrue(claim.waitForExistence(timeout: 10))
        claim.tap()
        XCTAssertTrue(app.staticTexts["Catch the Sun"].exists)
        XCTAssertFalse(app.buttons["Claim Journey Reward"].exists)
        let order = app.buttons["contract-action-0"]
        for _ in 0..<6 {
            if order.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(order.isHittable)
        order.tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Deliver'"), object: order)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        order.tap()
        XCTAssertEqual(order.label, "Accept")
        capture("varied_contracts")
    }

    func testProgressedCityScreenshots() throws {
        continueAfterFailure = false
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "60000"
        app.launchEnvironment["ISLORA_TEST_SAVE_NAME"] = "islora-screenshot-\(UUID()).json"
        app.launch()
        let freshCity = app.buttons["Claim"].waitForExistence(timeout: 10)
        if freshCity {
        app.buttons["Claim"].tap()
        openPlot(0)
        place("foundation_basic", x: -2, y: 0)
        place("foundation_basic", x: -1, y: 0)
        place("farm_field", x: -2, y: 1)
        place("farm_field", x: -1, y: 1)
        app.buttons["Done"].tap()
        app.buttons["Contracts"].tap()
        let foodOrder = app.buttons["contract-action-0"]
        for _ in 0..<8 {
            if foodOrder.isHittable { break }
            app.swipeUp()
        }
        for _ in 0..<80 {
            XCTAssertTrue(foodOrder.waitForExistence(timeout: 5))
            foodOrder.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Deliver'"), object: foodOrder)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            foodOrder.tap()
        }
        dismissSheet(title: "Contracts")
        } else if app.buttons["Collect"].waitForExistence(timeout: 2) {
            app.buttons["Collect"].tap()
        }
        openPlot(0)
        for x in 0...2 { place("foundation_basic", x: x, y: 0) }
        removeModule(-1, 1)
        place("structural_core", x: -1, y: 1)
        place("processing_unit", x: 0, y: 1)
        place("solar_panel", x: -1, y: 2)
        place("greenhouse", x: 1, y: 1)
        place("water_tank", x: 2, y: 1)
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reinforce'")).firstMatch.exists {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reinforce'")).firstMatch.tap()
        }
        saveBlueprint("Coastal Harvest")
        app.buttons["Done"].tap()

        unlockPlot(1)
        openPlot(1)
        app.buttons["Power Plant"].tap()
        for x in -2...2 { place("foundation_basic", x: x, y: 0) }
        place("structural_core", x: -1, y: 1)
        place("power_generator", x: 0, y: 1)
        place("battery_bank", x: 1, y: 1)
        place("solar_panel", x: -2, y: 1)
        place("office_basic", x: 2, y: 1)
        saveBlueprint("Coastal Power")
        app.buttons["Done"].tap()

        unlockPlot(2)
        openPlot(2)
        app.buttons["Data Center"].tap()
        for x in -2...2 { place("foundation_basic", x: x, y: 0) }
        place("structural_core", x: 0, y: 1)
        place("solar_panel", x: -2, y: 1)
        place("server_rack", x: -1, y: 1)
        place("server_rack", x: 1, y: 1)
        place("cooling_unit", x: 2, y: 1)
        place("solar_panel", x: 0, y: 2)
        saveBlueprint("Island Data Hub")
        app.buttons["Done"].tap()
        for index in 3...5 {
            unlockPlot(index)
        }

        // End fast-forward before photographing: the screenshots use normal game time.
        app.terminate()
        app.launchEnvironment["ISLORA_TEST_TIME_SCALE"] = "1"
        app.launch()
        if app.buttons["Collect"].waitForExistence(timeout: 2) { app.buttons["Collect"].tap() }
        settle()
        capture("01_overview")
        openPlot(0)
        settle()
        capture("02_farm_construction")
        app.buttons["Done"].tap()
        app.buttons["Contracts"].tap()
        let order = app.buttons["contract-action-0"]
        for _ in 0..<8 {
            if order.isHittable { break }
            app.swipeUp()
        }
        order.tap()
        app.swipeDown()
        settle()
        capture("03_contracts")
        dismissSheet(title: "Contracts")
        app.buttons["Profile"].tap()
        settle()
        capture("04_profile")
        dismissSheet(title: "Profile")
        app.buttons["Codex"].tap()
        settle()
        capture("05_codex")
        dismissSheet(title: "Codex")
        app.buttons["Project"].tap()
        let contribute = app.buttons.matching(identifier: "+200").allElementsBoundByIndex
        for button in contribute where button.isEnabled { button.tap() }
        settle()
        capture("06_world_project")
        dismissSheet(title: "World Project")
        openPlot(1)
        settle()
        capture("07_power_plant")
        app.buttons["Done"].tap()
        openPlot(2)
        settle()
        capture("08_data_center")
        app.buttons["Done"].tap()
        openPlot(3)
        app.buttons["Farm"].tap()
        XCTAssertTrue(app.buttons["Coastal Harvest"].waitForExistence(timeout: 5))
        capture("09_blueprint_picker")
        app.buttons["Coastal Harvest"].tap()
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        settle()
        capture("10_settings")
    }

    func removeModule(_ x: Int, _ y: Int) {
        grid(x, y).tap()
        XCTAssertTrue(app.alerts.buttons["Remove Module"].waitForExistence(timeout: 3))
        app.alerts.buttons["Remove Module"].tap()
    }

    func settle() { Thread.sleep(forTimeInterval: 4) }

    func grid(_ x: Int, _ y: Int) -> XCUICoordinate {
        app.buttons["camera-fit"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let tools = app.otherElements["construction-tools"]
        XCTAssertTrue(tools.exists)
        let top = app.buttons["camera-fit"].frame.maxY + 12
        let bottom = tools.frame.minY - 12
        let width = app.frame.width - 24
        let height = max(80, bottom - top)
        let lastRow = min(5, max(2, (topRows[activePlot] ?? 0) + 1))
        let scale = min(4, max(0.25, max(392 / width, (Double(lastRow + 1) * 72 + 32) / height)))
        let centerY = Double(lastRow) * 36
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: app.frame.width / 2 + Double(x) * 72 / scale,
            dy: top + height / 2 + (centerY - Double(y) * 72) / scale))
    }

    func openPlot(_ index: Int) {
        activePlot = index
        panToPlot(index)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 95 / 1.65)).tap()
    }

    func panToPlot(_ index: Int) {
        if !app.buttons["camera-fit"].exists {
            XCTAssertEqual(index, 0)
            return // A fresh city has no building/camera toolbar yet.
        }
        // A full right swipe returns to the first plot, then left drags reveal the requested plot.
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        app.buttons["camera-fit"].tap()
        for _ in 0..<6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.48))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.48)))
        }
        app.buttons["camera-fit"].tap()
        let distance = Double(index) * 432 / 1.65
        var remaining = distance
        let maxDrag = app.frame.width * 0.65
        while remaining > 0.1 {
            let step = min(remaining, maxDrag)
            middle.withOffset(CGVector(dx: step / 2, dy: 0))
                .press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: -step / 2, dy: 0)))
            remaining -= step
        }
    }

    func unlockPlot(_ index: Int) {
        openPlot(index)
        XCTAssertTrue(app.buttons["Unlock"].waitForExistence(timeout: 5))
        app.buttons["Unlock"].tap()
        Thread.sleep(forTimeInterval: 1)
    }

    func scrollTray(up: Bool) {
        let scroll = app.scrollViews.allElementsBoundByIndex.last!
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: up ? 0.9 : 0.1))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: up ? 0.1 : 0.9)))
    }

    func place(_ definition: String, x: Int, y: Int) {
        let icon = app.descendants(matching: .any).matching(identifier: "module-" + definition).firstMatch
        for _ in 0..<3 {
            if icon.exists && icon.isHittable { break }
            scrollTray(up: false)
        }
        for _ in 0..<4 {
            if icon.exists && icon.isHittable { break }
            scrollTray(up: true)
        }
        XCTAssertTrue(icon.exists && icon.isHittable, definition)
        icon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: grid(x, y))
        topRows[activePlot] = max(topRows[activePlot] ?? 0, y)
    }

    func saveBlueprint(_ name: String) {
        app.buttons["square.and.arrow.down"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText(name)
        app.alerts.buttons["Save"].tap()
    }

    func dismissSheet(title: String) {
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        } else if !app.buttons["Settings"].isHittable {
            XCTFail("Missing Close button on \(title)")
        }
        XCTAssertTrue(app.buttons["Settings"].isHittable)
    }

    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
