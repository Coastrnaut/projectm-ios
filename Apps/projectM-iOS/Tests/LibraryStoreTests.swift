// Feature 002 T225: the full-library purchase with StoreKit's local test environment
// (`projectM-iOS.storekit`, SKTestSession): purchase unlocks; cancel, failure and Ask to Buy unlock
// nothing; a later approval unlocks; a refund locks; restore unlocks; no UserDefaults key is written
// (FR-105-FR-110). Simulator results are not device evidence (T239 covers a device).
import StoreKitTest
import XCTest
@testable import projectM_iOS

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
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

    private func startedStore() async -> LibraryStore {
        let store = LibraryStore()
        await store.start()
        await store.loadProduct()
        return store
    }

    func testProductLoadsWithALocalizedPrice() async {
        let store = await startedStore()
        XCTAssertEqual(store.displayPrice, "$1.99")
        XCTAssertFalse(store.isUnlocked)
        XCTAssertEqual(store.state, .idle)
    }

    func testPurchaseUnlocksAndReportsTheChange() async {
        let store = await startedStore()
        var changes: [Bool] = []
        store.onEntitlementChange = { changes.append($0) }
        await store.purchase()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertEqual(store.state, .purchased)
        XCTAssertEqual(changes, [true])
        let relaunched = await startedStore()
        XCTAssertTrue(relaunched.isUnlocked, "read from StoreKit at launch (FR-107)")
    }

    func testFailureUnlocksNothing() async {
        session.failTransactionsEnabled = true
        let store = await startedStore()
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)
        if case .failed = store.state {} else { XCTFail("state \(store.state)") }
    }

    /// Ask to Buy: a pending result unlocks nothing; the approval arrives later as a transaction
    /// outside the purchase call and unlocks while the app runs (FR-108). A real Ask to Buy purchase
    /// is not used: in StoreKit's local test environment it asks for an Apple Account sign-in,
    /// which hangs an unattended run. The device sandbox run (T239) covers the real sheet.
    func testPendingUnlocksNothingThenALaterApprovalUnlocks() async throws {
        let store = await startedStore()
        var changes: [Bool] = []
        store.onEntitlementChange = { changes.append($0) }
        await store.handle(.pending)
        XCTAssertEqual(store.state, .pending)
        XCTAssertEqual(store.state.message, "Waiting for approval")
        XCTAssertFalse(store.isUnlocked)
        _ = try await session.buyProduct(identifier: LibraryStore.productID)   // the approval
        for _ in 0..<50 where !store.isUnlocked { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(store.isUnlocked, "approval arriving while the app runs unlocks (FR-108)")
        XCTAssertEqual(changes, [true])
    }

    func testCancelUnlocksNothing() async {
        let store = await startedStore()
        await store.handle(.userCancelled)
        XCTAssertEqual(store.state, .cancelled)
        XCTAssertEqual(store.state.message, "Purchase cancelled")
        XCTAssertFalse(store.isUnlocked)
    }

    func testRefundLocksAgain() async throws {
        let store = await startedStore()
        await store.purchase()
        XCTAssertTrue(store.isUnlocked)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        for _ in 0..<50 where store.isUnlocked {
            try await Task.sleep(for: .milliseconds(100))
            await store.refreshEntitlement()
        }
        XCTAssertFalse(store.isUnlocked, "FR-109")
    }

    func testRestoreFindsAnEarlierPurchase() async throws {
        try await session.buyProduct(identifier: LibraryStore.productID)
        let store = LibraryStore()
        await store.restore()
        XCTAssertTrue(store.isUnlocked)
    }

    func testNoUnlockFlagIsStored() async {
        let before = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let store = await startedStore()
        await store.purchase()
        let added = Set(UserDefaults.standard.dictionaryRepresentation().keys).subtracting(before)
        XCTAssertTrue(added.filter { $0.localizedCaseInsensitiveContains("unlock") || $0.localizedCaseInsensitiveContains("library") }.isEmpty,
                      "FR-110: \(added)")
    }
}
