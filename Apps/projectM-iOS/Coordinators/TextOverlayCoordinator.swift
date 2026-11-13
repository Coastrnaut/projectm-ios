// TextOverlayCoordinator.swift — the Text editor's model (MED-009-R2, R3, R10, R12).
//
// `spec` is the saved message and style: every change is saved at once (a few hundred bytes) and
// handed to `onSpecChange` (the app coordinator sets the text layer's spec). `setMessage` cleans
// typed or pasted text (TextSanitizer) and sets `messageWasCut` when the 280-character limit cut it,
// which the editor shows as a note. Main actor: the editor and the visual live there.
import Foundation
import Observation
import TextLayer

@MainActor
@Observable
final class TextOverlayCoordinator {
    static let cutNote = "Text is limited to \(TextSanitizer.maximumCharacters) characters and \(TextSanitizer.maximumLines) lines."

    var spec: TextOverlaySpec {
        didSet {
            guard spec != oldValue else { return }
            store.save(spec)
            onSpecChange?(spec)
        }
    }
    /// The last message change was cut by the limit.
    private(set) var messageWasCut = false

    @ObservationIgnored private let store: TextOverlayStore
    @ObservationIgnored var onSpecChange: ((TextOverlaySpec) -> Void)?

    init(store: TextOverlayStore) {
        self.store = store
        spec = store.load()
    }

    static func makeDefault(defaults: UserDefaults) -> TextOverlayCoordinator {
        TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
    }

    /// The message as typed; stored cleaned (control characters removed, limits applied).
    func setMessage(_ raw: String) {
        var next = spec
        messageWasCut = next.setMessage(raw)
        spec = next
    }

    /// Reset Text: empty message, default style (MED-009-R12).
    func reset() {
        messageWasCut = false
        spec = .default
        store.reset()
    }

    /// "No text", or the message (VoiceOver value of the visual, MED-009-R13).
    static func accessibilityValue(_ spec: TextOverlaySpec) -> String {
        spec.isEmpty ? "No text" : spec.message
    }
}
