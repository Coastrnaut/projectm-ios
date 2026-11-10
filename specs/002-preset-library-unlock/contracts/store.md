# Contract: LibraryStore (feature 002, app target)

```swift
@MainActor protocol EntitlementProviding: AnyObject {
    var isUnlocked: Bool { get }                  // FR-105, FR-110: from StoreKit only
    var displayPrice: String? { get }             // localized; nil while loading or unavailable
    var state: PurchaseState { get }
    func start() async                            // load product, read currentEntitlements, listen to Transaction.updates
    func purchase() async                         // FR-106, FR-108
    func restore() async                          // AppStore.sync()
}

enum PurchaseState: Equatable {
    case idle, loading, unavailable               // store or product unavailable (edge case)
    case purchasing, purchased, cancelled, pending, failed(String)
}
```

- Product id: `org.projectmios.ProjectMiOS.fullLibrary` (non-consumable).
- `isUnlocked` is true only for a verified, unrevoked transaction of that product; it flips on
  `Transaction.updates` (Ask to Buy approval, refund) without a relaunch (FR-107-FR-109).
- Messages (non-modal, FR-108): cancelled "Purchase cancelled", pending "Waiting for approval",
  failed "Purchase failed: <reason>", unavailable "The App Store isn't available right now".
- `FakeEntitlements` (DEBUG, UI tests): `-uitestUnlocked YES|NO` launch argument.
