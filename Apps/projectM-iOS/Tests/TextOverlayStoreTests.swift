// TextOverlayStoreTests.swift — MED-009-T16, T19: the saved text (MED-009-R3, R10 to R13; S1, S6).
// Each test uses its own UserDefaults suite; "relaunch" is a new store/coordinator on the same
// defaults.
import Foundation
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class TextOverlayStoreTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "TextOverlayStoreTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testSavedTextIsRestoredAfterARelaunch() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let texts = TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
        XCTAssertEqual(texts.spec, .default, "a fresh install: defaults, empty message")
        var reported: [TextOverlaySpec] = []
        texts.onSpecChange = { (spec: TextOverlaySpec) in reported.append(spec) }
        texts.setMessage("Hello 👋🏽 مرحبا")
        texts.spec.font = .menlo
        texts.spec.alignment = .trailing
        texts.spec.showsBox = true
        XCTAssertEqual(reported.count, 4, "every change is handed to the layer")
        let relaunched = TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
        XCTAssertEqual(relaunched.spec, texts.spec, "identical after a relaunch")
        XCTAssertEqual(relaunched.spec.message, "Hello 👋🏽 مرحبا")
        XCTAssertEqual(Array(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys), [TextOverlayStore.key], "one settings key")
    }

    func testMessagesAreCleanedAndCutsAreReported() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let texts = TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
        texts.setMessage("a\u{1B}b\tc")
        XCTAssertEqual(texts.spec.message, "ab c")
        XCTAssertFalse(texts.messageWasCut)
        texts.setMessage(String(repeating: "🇺🇦", count: 300))
        XCTAssertTrue(texts.messageWasCut)
        XCTAssertEqual(texts.spec.message.count, 280)
    }

    func testDamagedValuesAreRemovedAndNewerVersionsAreKept() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("garbage".utf8), forKey: TextOverlayStore.key)
        XCTAssertEqual(TextOverlayStore(defaults: defaults).load(), .default)
        XCTAssertNil(defaults.object(forKey: TextOverlayStore.key), "a damaged value is removed")
        let newer = Data(#"{"version":9,"message":"from the future"}"#.utf8)
        defaults.set(newer, forKey: TextOverlayStore.key)
        XCTAssertEqual(TextOverlayStore(defaults: defaults).load(), .default, "not shown")
        XCTAssertEqual(defaults.data(forKey: TextOverlayStore.key), newer, "left untouched")
        defaults.set("a string", forKey: TextOverlayStore.key)
        XCTAssertEqual(TextOverlayStore(defaults: defaults).load(), .default, "a wrong type reads as no text")
    }

    func testResetRestoresDefaultsAndClearsTheMessage() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let texts = TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
        texts.setMessage("styled")
        texts.spec.weight = .regular
        texts.spec.size = 0.2
        texts.reset()
        XCTAssertEqual(texts.spec, .default)
        XCTAssertEqual(TextOverlayStore(defaults: defaults).load(), .default, "saved")
        texts.setMessage(" \n ")
        XCTAssertEqual(TextOverlayCoordinator.accessibilityValue(texts.spec), "No text", "blank reads as no text")
        texts.setMessage("Hi")
        XCTAssertEqual(TextOverlayCoordinator.accessibilityValue(texts.spec), "Hi")
    }

    func testTextIsAPersistedChoice() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(VisualChoice.text.title, "Text")
        XCTAssertTrue(VisualChoice.text.usesText)
        XCTAssertTrue(VisualChoice.text.replacesProjectM)
        XCTAssertFalse(VisualChoice.text.isNative)
        XCTAssertFalse(VisualChoice.text.usesCamera)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.visual = .text
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .text, "restored after a relaunch (R11)")
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.textOverlayKey), "the UI-test reset clears it")
        #if DEBUG
        XCTAssertEqual(VisualizerView.textRenderingValue(.ready(width: 12, height: 3, checksum: 0xab)), "12x3 00000000000000ab")
        XCTAssertEqual(VisualizerView.textRenderingValue(.empty), "none")
        #endif
    }
}
