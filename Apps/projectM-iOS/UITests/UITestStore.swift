// UITestStore.swift — every UI test except PurchaseUITests launches the app with a fixed, locked
// entitlement (`-uitestUnlocked NO`, FakeEntitlements). Otherwise the app's real StoreKit store asks
// the App Store, and the simulator puts up an Apple Account sign-in prompt that stalls the run.
import XCTest

extension XCTestCase {
    static let noStore = ["-uitestUnlocked", "NO"]
}
