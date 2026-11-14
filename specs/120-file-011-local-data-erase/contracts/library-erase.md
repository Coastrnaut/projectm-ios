# Contract: Library erase (FILE-011)

## E1 Policy
`LibraryErasePolicy.folders(_:)`, `.settingKeys(_:)`, `.neverErasedKeys`. The union of all
categories' keys and `neverErasedKeys` is disjoint; every folder name is one the stores use (app test).

## E2 Inventory
`LibraryEraseInventory.measure(root:settings:) -> [LibraryEraseCategory: LibraryEraseInventory.Item]`.
Reads only.

## E3 Plan
`LibraryErasePlanner.plan(_ categories: Set<LibraryEraseCategory>, root: URL, settings:) -> LibraryErasePlan`.
Reads only; deterministic.

## E4 Run
`LibraryEraser(root:).run(_ plan:, removeSettings: ([String]) -> Void) -> LibraryEraseOutcome`
(`.erased(categories)`, `.failed`, `.refused(message)`). All or nothing as in research D2; a fault
before the commit leaves the tree snapshot of every library root identical; `removeSettings` and the
media releases run only after the commit.

## E5 Recover
`LibraryEraser.recover(removeSettings:) -> Bool`: prepared → rolled back; committed → finished.

## E6 Request and launch
`LibraryEraseRequestStore(root:)`: `save(_:)`, `pending`, `cancel()`, `takeResult()`.
`LibraryEraseLaunch.run(root:settings:removeSettings:) -> LibraryEraseResultNote?`: recover, then run a
pending request once and record its result; the request is removed after the attempt.

## E7 App
`LibraryEraseCoordinator`: `refresh()` (inventory, pending, result once + announcement on the
`library` lane), `selection`, `requestErase()`, `cancelErase()`; disabled while a restore is pending.
Accessibility identifiers: `libraryEraseButton`, `libraryEraseRow.<category>`, `libraryEraseSelectAll`,
`libraryEraseBackUpFirst`, `libraryEraseContinue`, `libraryEraseConfirm`, `libraryErasePending`,
`libraryEraseCancelPending`, `libraryEraseMessage`, `libraryEraseDismiss`.
