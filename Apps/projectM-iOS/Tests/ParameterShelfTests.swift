// ParameterShelfTests.swift — UIX-004-T07, T09, T10 (specs/151-uix-004-parameter-shelf; S1-S3).
//
// * Acceptance 1 (S1): three pins survive a rebuild from the same defaults, in the same order.
// * Acceptance 2 (S2): a stored list with an unknown ID and garbage shows only the valid pins, the note counts
//   exactly the unavailable entries, nothing crashes, and Remove deletes only those entries.
// * Order changes (move, Move up, Move down) persist; the limit of 8; read-only and unknown IDs cannot be pinned.
// * S3: a value written through a shelf control's target stores exactly what Settings stores.
// Each test makes its own UserDefaults suite and removes it; nothing is mutated in setUp/tearDown.
import Foundation
import LibraryBackup
import ParameterGraph
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterShelfTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "ParameterShelfTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    // MARK: Acceptance 1: pins persist in order (UIX-004-S1)

    func testThreePinsComeBackInTheSameOrderAfterARelaunch() throws {
        let (defaults, name) = try makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let shelf = ParameterShelf(defaults: defaults)
        XCTAssertTrue(shelf.pinned.isEmpty, "a fresh install has no pins")
        let order: [ParameterID] = [IDs.circularSpectrumBarCount, IDs.bloomIntensity, IDs.bloomEnabled]
        for id in order { XCTAssertTrue(shelf.pin(id), "\(id)") }

        let relaunched = ParameterShelf(defaults: defaults)
        XCTAssertEqual(relaunched.pinned, order, "the same pins in the same order")
        XCTAssertNil(relaunched.missingNote)
        XCTAssertEqual(defaults.stringArray(forKey: ParameterShelf.pinsKey), order.map(\.rawValue))
    }

    // MARK: Acceptance 2: missing IDs are reported safely (UIX-004-S2)

    func testUnknownAndGarbageEntriesAreCountedReportedAndRemovedAlone() throws {
        let (defaults, name) = try makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let stored: [Any] = [IDs.bloomRadius.rawValue, "effect.bloom.removedInAFutureVersion", "%%garbage",
                             IDs.linearSpectrumSpacing.rawValue, 42, IDs.bloomRadius.rawValue]   // a non-string and a duplicate
        defaults.set(stored, forKey: ParameterShelf.pinsKey)

        let shelf = ParameterShelf(defaults: defaults)   // no crash
        XCTAssertEqual(shelf.pinned, [IDs.bloomRadius, IDs.linearSpectrumSpacing], "only the valid pins, in order")
        XCTAssertEqual(shelf.missing.count, 3, "the unknown ID, the garbage string and the non-string")
        XCTAssertEqual(shelf.missingNote, "3 pinned controls are no longer available")

        let reloaded = ParameterShelf(defaults: defaults)
        XCTAssertEqual(reloaded.missing.count, 3, "unknown entries are kept until the user removes them")
        shelf.pin(IDs.bloomEnabled)   // a change saves; the unknown entries are still kept
        XCTAssertEqual(ParameterShelf(defaults: defaults).missing.count, 3)

        shelf.removeMissing()
        XCTAssertEqual(shelf.pinned, [IDs.bloomRadius, IDs.linearSpectrumSpacing, IDs.bloomEnabled])
        XCTAssertTrue(shelf.missing.isEmpty)
        XCTAssertNil(shelf.missingNote)
        XCTAssertEqual(defaults.stringArray(forKey: ParameterShelf.pinsKey),
                       [IDs.bloomRadius.rawValue, IDs.linearSpectrumSpacing.rawValue, IDs.bloomEnabled.rawValue],
                       "Remove deleted only the unavailable entries")
    }

    func testCorruptShapesBecomeOneUnavailableEntryEach() throws {
        let (defaults, name) = try makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        defaults.set(7, forKey: ParameterShelf.pinsKey)   // not a list
        let shelf = ParameterShelf(defaults: defaults)
        XCTAssertTrue(shelf.pinned.isEmpty)
        XCTAssertEqual(shelf.missingNote, "1 pinned control is no longer available")
        // A registered parameter without a control (read-only) is unavailable too.
        XCTAssertEqual(ParameterShelfStorage.decode(nil), [])
        defaults.set([IDs.bloomKnee.rawValue], forKey: ParameterShelf.pinsKey)
        XCTAssertEqual(ParameterShelf(defaults: defaults).missing, [IDs.bloomKnee.rawValue])
    }

    // MARK: Order and limit (UIX-004-R2, R6)

    func testOrderChangesPersist() throws {
        let (defaults, name) = try makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        defaults.set(["unknown.id"], forKey: ParameterShelf.pinsKey)
        let shelf = ParameterShelf(defaults: defaults)
        for id in [IDs.bloomIntensity, IDs.bloomRadius, IDs.bloomThreshold] { shelf.pin(id) }
        shelf.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(shelf.pinned, [IDs.bloomThreshold, IDs.bloomIntensity, IDs.bloomRadius])
        shelf.moveDown(IDs.bloomThreshold)
        XCTAssertEqual(shelf.pinned, [IDs.bloomIntensity, IDs.bloomThreshold, IDs.bloomRadius])
        shelf.moveUp(IDs.bloomIntensity)   // already first: no change
        shelf.moveDown(IDs.bloomRadius)    // already last: no change
        XCTAssertEqual(ParameterShelf(defaults: defaults).pinned, [IDs.bloomIntensity, IDs.bloomThreshold, IDs.bloomRadius])
        XCTAssertEqual(ParameterShelf(defaults: defaults).missing, ["unknown.id"], "reordering keeps unknown entries")
        shelf.remove(atOffsets: IndexSet(integer: 1))
        XCTAssertEqual(ParameterShelf(defaults: defaults).pinned, [IDs.bloomIntensity, IDs.bloomRadius])
    }

    func testTheLimitIsEightAvailablePinsAndOnlyEditableIDsArePinnable() throws {
        let (defaults, name) = try makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        defaults.set(["unknown.a", "unknown.b"], forKey: ParameterShelf.pinsKey)
        // Ten stand-in available IDs make the limit testable (the app has seven editable parameters).
        let ids: [ParameterID] = (0..<10).map { (i: Int) -> ParameterID in ParameterID("test.p\(i)") }
        let shelf = ParameterShelf(defaults: defaults) { (id: ParameterID) -> Bool in id.rawValue.hasPrefix("test.") }
        for id in ids.prefix(8) { XCTAssertTrue(shelf.pin(id)) }
        XCTAssertFalse(shelf.canPin, "unknown entries do not count, eight available pins do")
        XCTAssertFalse(shelf.pin(ids[8]), "the ninth pin is refused")
        XCTAssertEqual(shelf.pinned.count, 8)
        shelf.unpin(ids[0])
        XCTAssertTrue(shelf.pin(ids[8]), "unpinning frees a slot")
        XCTAssertFalse(shelf.pin(ids[8]), "no duplicates")
        XCTAssertEqual(ParameterShelf.fullTitle, "Shelf Full (8)")

        let real = ParameterShelf(defaults: defaults)
        XCTAssertFalse(real.pin(IDs.bloomKnee), "read-only parameters cannot be pinned")
        XCTAssertFalse(real.pin(ParameterID("not.registered")))
        XCTAssertNil(real.actionTitle(IDs.bloomKnee))
        XCTAssertEqual(real.actionTitle(IDs.bloomIntensity), "Pin to Shelf")
        XCTAssertTrue(ParameterInspectorTargets.inspectableIDSet == Set(ParameterInspectorTargets.inspectableIDs))
    }

    // MARK: A shelf write equals a Settings write (UIX-004-S3)

    func testWritingThroughTheShelfEqualsWritingThroughSettings() throws {
        let (shelfDefaults, shelfName) = try makeDefaults()
        let (settingsDefaults, settingsName) = try makeDefaults()
        defer {
            UserDefaults().removePersistentDomain(forName: shelfName)
            UserDefaults().removePersistentDomain(forName: settingsName)
        }
        let viaShelf = AppSettings(defaults: shelfDefaults, systemReduceMotion: false)
        let viaSettings = AppSettings(defaults: settingsDefaults, systemReduceMotion: false)

        // The shelf control writes through UIX-003's target (`ParameterShelfControl`).
        let intensity = try XCTUnwrap(ParameterInspectorTargets.target(for: IDs.bloomIntensity, settings: viaShelf))
        intensity.set(.continuous(0.73))
        try XCTUnwrap(ParameterInspectorTargets.target(for: IDs.bloomEnabled, settings: viaShelf)).set(.boolean(true))
        try XCTUnwrap(ParameterInspectorTargets.target(for: IDs.circularSpectrumBarCount, settings: viaShelf)).set(.enumeration("128"))

        // Settings: the Intensity slider's target, the Glow toggle and the Bars picker bindings.
        SettingsView.glowTarget(viaSettings, \.glowIntensity).set(0.73)
        viaSettings.glowEnabled = true
        viaSettings.circularSpectrumBars = 128

        let keys: [String] = [AppSettings.glowIntensityKey, AppSettings.glowKey, AppSettings.circularSpectrumBarsKey]
        for key in keys {
            let shelfValue = shelfDefaults.object(forKey: key) as? NSObject
            let settingsValue = settingsDefaults.object(forKey: key) as? NSObject
            XCTAssertNotNil(shelfValue, key)
            XCTAssertEqual(shelfValue, settingsValue, "\(key): the shelf stores exactly what Settings stores")
        }
        XCTAssertEqual(viaShelf.glowIntensity.bitPattern, viaSettings.glowIntensity.bitPattern)
    }

    /// UIX-004-R10: the pins travel in a library backup (string list) and restore in order.
    func testThePinsTravelInALibraryBackup() throws {
        let (source, sourceName) = try makeDefaults()
        let (target, targetName) = try makeDefaults()
        defer {
            UserDefaults().removePersistentDomain(forName: sourceName)
            UserDefaults().removePersistentDomain(forName: targetName)
        }
        XCTAssertTrue(LibrarySettingsPolicy.isIncluded(ParameterShelf.pinsKey))
        XCTAssertFalse(LibrarySettingsPolicy.excludedKeys.contains(ParameterShelf.pinsKey))
        let shelf = ParameterShelf(defaults: source)
        shelf.pin(IDs.bloomThreshold)
        shelf.pin(IDs.linearSpectrumOrientation)
        let values: [String: LibrarySettingValue] = LibrarySettingsBridge.read(source)
        XCTAssertEqual(values[ParameterShelf.pinsKey], .strings([IDs.bloomThreshold.rawValue, IDs.linearSpectrumOrientation.rawValue]))
        LibrarySettingsBridge.apply(values, to: target)
        XCTAssertEqual(ParameterShelf(defaults: target).pinned, [IDs.bloomThreshold, IDs.linearSpectrumOrientation])
    }

    func testTheNoteNamesTheExactCount() {
        XCTAssertNil(ParameterShelf.missingNote(count: 0))
        XCTAssertEqual(ParameterShelf.missingNote(count: 1), "1 pinned control is no longer available")
        XCTAssertEqual(ParameterShelf.missingNote(count: 2), "2 pinned controls are no longer available")
    }
}
