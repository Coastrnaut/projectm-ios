// LibraryStore.swift — the full-library purchase (feature 002 US2; contracts/store.md; research
// R-24). StoreKit 2 only: the product loads with Product.products(for:), the entitlement comes from
// Transaction.currentEntitlements at launch and Transaction.updates while running, restore is
// AppStore.sync(). The app never stores an unlock flag (FR-110); StoreKit keeps entitlements on the
// device, so the unlock works offline (FR-107). No server, no network code of our own (FR-122).
import Foundation
import Observation
import StoreKit

enum PurchaseState: Equatable {
    case idle, loading, unavailable, restricted
    case purchasing, purchased, cancelled, pending
    case failed(String)

    /// The non-modal message for this state (FR-108, spec Edge Cases), or nil.
    var message: String? {
        switch self {
        case .cancelled: "Purchase cancelled"
        case .pending: "Waiting for approval"
        case .failed(let reason): "Purchase failed: \(reason)"
        case .unavailable: "The App Store isn't available right now"
        case .restricted: "Purchases aren't allowed on this device"
        default: nil
        }
    }
}

@MainActor
protocol EntitlementProviding: AnyObject {
    var isUnlocked: Bool { get }
    var displayPrice: String? { get }
    var state: PurchaseState { get }
    /// Called on every entitlement change (unlock, Ask to Buy approval, refund).
    var onEntitlementChange: ((Bool) -> Void)? { get set }
    /// The entitlement from StoreKit's local records, and the updates listener. Fast and offline;
    /// the library is ready to browse after this (SC-101).
    func start() async
    /// The product and its localized price (an App Store request); not needed to browse.
    func loadProduct() async
    func purchase() async
    func restore() async
}

@MainActor
@Observable
final class LibraryStore: EntitlementProviding {
    static let productID = "org.projectmios.ProjectMiOS.fullLibrary"

    private(set) var isUnlocked = false
    private(set) var displayPrice: String?
    private(set) var state: PurchaseState = .idle
    /// Called on every entitlement change (unlock, Ask to Buy approval, refund).
    @ObservationIgnored var onEntitlementChange: ((Bool) -> Void)?
    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// The App Store purchase call. Tests replace it: in StoreKit's local test environment a
    /// purchase with failing transactions turned on sometimes never returns (it hung
    /// LibraryStoreTests.testFailureUnlocksNothing past 3 minutes three times on 2026-11-12/13),
    /// so the failure path is tested by making this call throw. Production always uses StoreKit.
    @ObservationIgnored var performPurchase: (Product) async throws -> Product.PurchaseResult = {
        try await $0.purchase()
    }

    isolated deinit { updates?.cancel() }

    func start() async {
        state = .loading
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        await refreshEntitlement()
        // Spec Edge Cases: Screen Time can forbid purchases; the sheet says so as soon as it opens.
        state = AppStore.canMakePayments ? .idle : .restricted
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
            displayPrice = product?.displayPrice
            if state != .restricted { state = product == nil ? .unavailable : .idle }
        } catch {
            state = .unavailable
        }
    }

    func purchase() async {
        guard AppStore.canMakePayments else { state = .restricted; return }
        if product == nil { product = try? await Product.products(for: [Self.productID]).first }
        guard let product else { state = .unavailable; return }
        state = .purchasing
        do {
            await handle(try await performPurchase(product))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The outcome of a purchase call (FR-107, FR-108). Separate so tests can give it each result:
    /// StoreKit's local test environment asks for an Apple Account sign-in for a real Ask to Buy
    /// purchase, which an unattended test cannot answer.
    func handle(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                state = .failed("the purchase could not be verified")
                return
            }
            await transaction.finish()
            await refreshEntitlement()
            state = isUnlocked ? .purchased : .failed("not unlocked")
        case .userCancelled:
            state = .cancelled
        case .pending:
            state = .pending
        @unknown default:
            state = .failed("unknown result")
        }
    }

    func restore() async {
        state = .loading
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            state = isUnlocked ? .purchased : .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// True only for a verified, unrevoked transaction of the product (FR-109, FR-110).
    func refreshEntitlement() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        if owned != isUnlocked {
            isUnlocked = owned
            onEntitlementChange?(owned)
        }
    }
}

#if DEBUG || PROJECTM_AUTOMATION
/// UI tests (`-uitestUnlocked YES|NO`) and device automation (AutomationRunner): a fixed entitlement without StoreKit.
@MainActor
@Observable
final class FakeEntitlements: EntitlementProviding {
    private(set) var isUnlocked: Bool
    let displayPrice: String? = "$1.99"
    private(set) var state: PurchaseState = .idle
    @ObservationIgnored var onEntitlementChange: ((Bool) -> Void)?

    init(unlocked: Bool) { isUnlocked = unlocked }

    static func fromLaunchArguments() -> FakeEntitlements? {
        // Hosting unit tests: the app must not touch StoreKit before a test's SKTestSession exists.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return FakeEntitlements(unlocked: false) }
        guard UserDefaults.standard.object(forKey: "uitestUnlocked") != nil else { return nil }
        return FakeEntitlements(unlocked: UserDefaults.standard.bool(forKey: "uitestUnlocked"))
    }

    func start() async {}
    func loadProduct() async {}
    func purchase() async {
        isUnlocked = true
        state = .purchased
        onEntitlementChange?(true)
    }
    func restore() async { await purchase() }
}
#endif
