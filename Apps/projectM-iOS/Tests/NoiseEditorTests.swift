// SHD-006-T11: the Noise editor's store — defaults store nothing, edits persist across a relaunch, values are clamped,
// damaged stored data reads as defaults, "Randomize seed" follows the fixed sequence, reset clears the key, the key's
// backup policy, and the preview is drawn at 256 × 256 and changes with the seed (SHD-006-R6, R7).
import LibraryBackup
import ParameterGraph
import ProceduralMaterials
import XCTest
@testable import projectM_iOS

@MainActor
final class NoiseEditorTests: XCTestCase {
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "NoiseEditorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    private func id(_ store: NoiseEditorStore, _ name: String) -> ParameterID { store.definition.parameterID(name) }

    func testEditsPersistAndDefaultsStoreNothing() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let store = NoiseEditorStore(defaults: defaults, renderer: nil)
            XCTAssertNil(defaults.object(forKey: NoiseEditorStore.key), "nothing stored at defaults")
            XCTAssertEqual(store.controls.count, 11, "one control per Noise Flow parameter")
            store.set(id(store, "octaves"), .integer(6))
            store.set(id(store, "lacunarity"), .continuous(9))   // clamped to 3.5
            store.set(id(store, "warpAmount"), .continuous(.nan))   // refused: unchanged
            let reloaded = NoiseEditorStore(defaults: defaults, renderer: nil)
            XCTAssertEqual(reloaded.octaves, 6)
            XCTAssertEqual(reloaded.values.double(id(store, "lacunarity")), 3.5)
            XCTAssertEqual(reloaded.values.double(id(store, "warpAmount")), 0.8)
            XCTAssertEqual(reloaded.previewDescription, "Seed 0, 6 octaves")
            reloaded.resetToDefaults()
            XCTAssertNil(defaults.object(forKey: NoiseEditorStore.key))
            XCTAssertEqual(reloaded.values, MaterialParameterValues(reloaded.definition))
        }
    }

    func testDamagedStoredDataIsLenient() {
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set(Data("not json".utf8), forKey: NoiseEditorStore.key)
            let damaged = NoiseEditorStore(defaults: defaults, renderer: nil)
            XCTAssertEqual(damaged.values, MaterialParameterValues(damaged.definition))
            let mixed = #"{"gain": {"kind": "continuous", "value": 0.7}, "nope": {"kind": "integer", "value": 1}, "octaves": {"kind": "spiral", "value": 2}, "seed": {"kind": "continuous", "value": 3}}"#
            defaults.set(Data(mixed.utf8), forKey: NoiseEditorStore.key)
            let store = NoiseEditorStore(defaults: defaults, renderer: nil)
            XCTAssertEqual(store.seed, 0, "a value of the wrong kind is skipped")
            XCTAssertEqual(store.octaves, 3, "an undecodable value is skipped")
            XCTAssertEqual(store.values.double(id(store, "gain")) ?? 0, 0.7, accuracy: 1e-12, "valid entries are kept")
        }
    }

    func testRandomizeSeedFollowsTheFixedSequence() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let store = NoiseEditorStore(defaults: defaults, renderer: nil)
            var expected = NoiseSeedSequence()
            var current = 0
            for _ in 0..<3 {
                store.randomizeSeed()
                let next: Int = expected.next(after: current)
                XCTAssertEqual(store.seed, next)
                XCTAssertNotEqual(next, current)
                current = next
            }
            XCTAssertEqual(NoiseEditorStore(defaults: defaults, renderer: nil).seed, current, "saved")
        }
    }

    func testTheKeyIsBackedUpAndErasedWithSettings() {
        XCTAssertTrue(LibrarySettingsPolicy.isIncluded(NoiseEditorStore.key))
        XCTAssertTrue(LibraryErasePolicy.erasableKeys.contains(NoiseEditorStore.key))
    }

    func testPreviewIsDrawnAndFollowsTheSeed() throws {
        guard let renderer = NoiseEditorStore.sharedRenderer else { throw XCTSkip("No Metal device") }
        withDefaults { (defaults: UserDefaults) -> Void in
            let store = NoiseEditorStore(defaults: defaults, renderer: renderer)
            guard let first = store.preview else { return XCTFail("a preview") }
            XCTAssertEqual(first.width, NoiseEditorStore.previewSide)
            XCTAssertEqual(first.height, NoiseEditorStore.previewSide)
            let before: Data? = first.dataProvider?.data as Data?
            store.set(id(store, "seed"), .integer(1234))
            let after: Data? = store.preview?.dataProvider?.data as Data?
            XCTAssertNotNil(after)
            XCTAssertNotEqual(before, after, "a new seed redraws a different texture")
        }
    }
}
