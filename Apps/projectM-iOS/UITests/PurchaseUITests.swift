// Feature 002 T229: the purchase sheet with StoreKit's local test environment
// (`projectM-iOS.storekit`, SKTestSession, dialogs off). Sheet contents and price; Buy unlocks and
// switches the scope to Cream of the Crop (FR-107, FR-119); a failed purchase shows its message and
// unlocks nothing (FR-108). Simulator results are never device evidence; a sandbox run is T239.
import StoreKitTest
import XCTest

@MainActor
final class PurchaseUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var session: SKTestSession!

    override func setUp() async throws {
        continueAfterFailure = false
        session = try SKTestSession(configurationFileNamed: "projectM-iOS")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.failTransactionsEnabled = false
    }

    override func tearDown() async throws {
        session.clearTransactions()
    }

    private var scopeLine: XCUIElement { app.staticTexts["scopeLine"] }

    private func waitForScopeLine(_ text: String, timeout: TimeInterval = 10) {
        expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: scopeLine)
        waitForExpectations(timeout: timeout)
    }

    private func openPurchaseSheet() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics"]
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        app.buttons["In-App Playback"].tap()
        waitForScopeLine("Included · 28")
        let presets = app.buttons["presets"]
        if !presets.waitForExistence(timeout: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        presets.tap()
        let pack = app.buttons["node:cream-of-the-crop"]
        XCTAssertTrue(pack.waitForExistence(timeout: 10))
        pack.tap()
        let banner = app.buttons["unlockBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.label, "Unlock all 12,819 presets")
        banner.tap()
        XCTAssertTrue(app.buttons["buyLibrary"].waitForExistence(timeout: 5))
    }

    func testSheetShowsThePriceAndPacks() {
        openPurchaseSheet()
        let buy = app.buttons["buyLibrary"]
        let priced = NSPredicate(format: "label == %@", "Unlock for $1.99")
        expectation(for: priced, evaluatedWith: buy)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["purchaseSummary"].label.contains("12,819"))
        for pack in ["Cream of the Crop", "projectM Classic", "Milkdrop Original", "En D"] {
            XCTAssertTrue(app.staticTexts[pack].exists, pack)
        }
        XCTAssertTrue(app.buttons["restorePurchases"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    func testBuyUnlocksAndSwitchesTheScope() {
        openPurchaseSheet()
        let buy = app.buttons["buyLibrary"]
        expectation(for: NSPredicate(format: "label == %@", "Unlock for $1.99"), evaluatedWith: buy)
        waitForExpectations(timeout: 10)
        buy.tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 10), "the sheet closes after the purchase")
        let unlocked = app.buttons["node:cream-of-the-crop"]
        if unlocked.waitForExistence(timeout: 2) == false { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertFalse(app.buttons["unlockBanner"].exists, "the pack is unlocked")
        app.buttons["Done"].firstMatch.tap()
        waitForScopeLine("Cream of the Crop · 9728")
    }

    func testFailedPurchaseShowsTheMessageAndUnlocksNothing() {
        session.failTransactionsEnabled = true
        openPurchaseSheet()
        let buy = app.buttons["buyLibrary"]
        expectation(for: NSPredicate(format: "label == %@", "Unlock for $1.99"), evaluatedWith: buy)
        waitForExpectations(timeout: 10)
        buy.tap()
        let message = app.staticTexts["purchaseMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.hasPrefix("Purchase failed"), message.label)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["unlockBanner"].waitForExistence(timeout: 5), "still locked")
    }
}
