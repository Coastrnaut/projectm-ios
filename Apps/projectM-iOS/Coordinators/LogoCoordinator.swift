// LogoCoordinator.swift — the MED-010 logo in the app: picker results → LogoStore, placement, notices,
// announcements, and the live logo layers of the compositor visuals (MED-010-R1, R5 to R7, R9, R12, R14;
// research MED-010-D3, D4, D7; contracts/logo-overlay.md C8).
//
// * Photos: SwiftUI's `PhotosPicker` without a photo library (out of process, no permission); the item
//   arrives as a temporary file (`PickedImageFile`, MED-001), is imported and deleted. Files:
//   `fileImporter`, one image; the URL is read once by the store. Imports run off the main actor, one at a
//   time; a refused import keeps the current logo and shows `notice` (6 s, or until dismissed).
// * Placement edits are saved at once and pushed to every attached layer (shown from the next frame).
// * `attach(to:)` gives a compositor visual (Photo, Video, Text, Camera) its own `LogoLayerSource` as the
//   top stack entry (`Compositor.attachLogo`); layers are held weakly, so a released visual drops out.
// * Announcements go through the injected closure (the app wires the shared announcer, kind `library`).
import Compositor
import Foundation
import ImageLayer
import Metal
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class LogoCoordinator {
    static let noticeDuration: Duration = .seconds(6)
    static let storedCopyUnreadableMessage = "The logo couldn't be loaded."

    /// The current logo (nil: none).
    private(set) var logo: StoredPhoto?
    /// Where and how strongly it is drawn.
    private(set) var placement: LogoPlacement
    private(set) var isImporting = false
    private(set) var notice: String?
    /// The logo's pixel size once a layer has loaded it.
    private(set) var loadedSize: (width: Int, height: Int)?

    @ObservationIgnored private let store: LogoStore?
    @ObservationIgnored var announce: @MainActor (String) -> Void
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var layers: [WeakLogoLayer] = []

    init(store: LogoStore?, announce: @escaping @MainActor (String) -> Void = { (_: String) -> Void in }) {
        self.store = store
        self.announce = announce
        logo = store?.current()
        placement = store?.placement ?? .default
    }

    static func makeDefault(defaults: UserDefaults) -> LogoCoordinator {
        let photos: PhotoStore? = (try? PhotoStore.defaultDirectory()).map { (url: URL) -> PhotoStore in PhotoStore(directory: url, defaults: defaults) }
        return LogoCoordinator(store: photos.map { (p: PhotoStore) -> LogoStore in LogoStore(photos: p) })
    }

    /// "No logo", "Importing…", "Loading…" or "512 × 256".
    var summary: String {
        if isImporting { return "Importing…" }
        guard logo != nil else { return "No logo" }
        guard let size = loadedSize else { return "Loading…" }
        return "\(size.width) × \(size.height)"
    }

    // MARK: - Pickers

    func filePicked(_ result: Result<URL, any Error>) async {
        switch result {
        case .success(let url):
            await importLogo(at: url, deleteAfterwards: false)
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { show(LogoImport.message(for: .unreadable)) }
        }
    }

    func photoPicked(_ item: PhotosPickerItem) async {
        guard !isImporting else { return }
        isImporting = true
        let picked: PickedImageFile? = try? await item.loadTransferable(type: PickedImageFile.self)
        isImporting = false
        guard let picked else { show(LogoImport.message(for: .unreadable)); return }
        await importLogo(at: picked.url, deleteAfterwards: true)
    }

    /// Imports `url` off the main actor and publishes the result.
    func importLogo(at url: URL, deleteAfterwards: Bool) async {
        guard !isImporting else { return }
        guard let store else { show(LogoImport.message(for: .saveFailed)); return }
        isImporting = true
        let result: Result<StoredPhoto, ImageImportError> = await Task.detached(priority: .userInitiated) {
            defer { if deleteAfterwards { try? FileManager.default.removeItem(at: url) } }
            do throws(ImageImportError) {
                return .success(try store.importLogo(at: url))
            } catch {
                return .failure(error)
            }
        }.value
        isImporting = false
        switch result {
        case .success(let stored):
            setLogo(stored)
            clearNotice()
            announce("Logo chosen.")
        case .failure(let error):
            show(LogoImport.message(for: error))
        }
    }

    #if DEBUG
    /// UI tests only (UITestLogoFixture): a synchronous import before the first screen.
    func importNow(at url: URL) {
        guard let store else { return }
        do throws(ImageImportError) {
            setLogo(try store.importLogo(at: url))
        } catch {
            show(LogoImport.message(for: error))
        }
    }
    #endif

    /// Remove Logo: releases the copy and clears the identifier (the placement stays).
    func remove() {
        store?.remove()
        setLogo(nil)
        clearNotice()
        announce("Logo removed.")
    }

    // MARK: - Placement

    func setCorner(_ corner: LogoCorner) {
        setPlacement(placement.with(corner: corner))
        announce("Logo position: \(corner.title).")
    }

    func setSize(_ size: Double) { setPlacement(placement.with(size: size)) }
    func setMargin(_ margin: Double) { setPlacement(placement.with(margin: margin)) }
    func setOpacity(_ opacity: Double) { setPlacement(placement.with(opacity: opacity)) }

    func setPlacement(_ new: LogoPlacement) {
        guard new != placement else { return }
        placement = new
        store?.savePlacement(new)
        for layer in liveLayers() { layer.placement = new }
    }

    /// MED-010-R10, R11: a scene's logo (launch restore, Reopen, cues, archive import). A store ID whose
    /// picture is not on this device changes nothing; returns whether the logo was applied.
    @discardableResult
    func restore(storeID: String, placement new: LogoPlacement) -> Bool {
        guard let store, let id = UUID(uuidString: storeID), id.uuidString == storeID,
              let url = store.photos.existingFile(for: id) else { return false }
        let stored = StoredPhoto(id: id, url: url)
        if logo?.id != id {
            store.makeCurrent(stored)
            setLogo(stored)
        }
        setPlacement(new)
        return true
    }

    /// FILE-001: the archive import made a logo current in the store; publish it.
    func adoptCurrent(placement new: LogoPlacement) {
        setLogo(store?.current())
        setPlacement(new)
    }

    /// The identifier and placement for a captured scene (nil: no logo).
    var sceneValue: (storeID: String, placement: LogoPlacement)? {
        logo.map { (stored: StoredPhoto) -> (storeID: String, placement: LogoPlacement) in (stored.id.uuidString, placement) }
    }

    // MARK: - Layers (MED-010-R5)

    /// Gives `compositor` its logo layer (top of its stack) and returns it; nil when it has one or the stack
    /// refused it.
    @discardableResult
    func attach(to compositor: Compositor) -> LogoLayerSource? {
        let layer = LogoLayerSource(device: compositor.device)
        layer.placement = placement
        layer.content = logo.map { (stored: StoredPhoto) -> ImageLayerContent in .file(stored.url) } ?? .none
        layer.onStateChange = { [weak self] (state: ImageLayerState) in self?.layerStateChanged(state) }
        guard compositor.attachLogo(layer) else { return nil }
        layers = layers.filter { (box: WeakLogoLayer) -> Bool in box.layer != nil } + [WeakLogoLayer(layer)]
        return layer
    }

    /// Frames in which any live logo layer showed the logo (DEBUG probe, tests).
    var framesShown: Int { liveLayers().reduce(0) { (sum: Int, layer: LogoLayerSource) -> Int in sum + layer.framesShown } }

    private func liveLayers() -> [LogoLayerSource] { layers.compactMap { (box: WeakLogoLayer) -> LogoLayerSource? in box.layer } }

    private func layerStateChanged(_ state: ImageLayerState) {
        switch state {
        case .ready(let width, let height): loadedSize = (width, height)
        case .failed: if logo != nil { show(Self.storedCopyUnreadableMessage) }
        case .empty, .loading: loadedSize = nil
        }
    }

    private func setLogo(_ stored: StoredPhoto?) {
        logo = stored
        loadedSize = nil
        let content: ImageLayerContent = stored.map { (s: StoredPhoto) -> ImageLayerContent in .file(s.url) } ?? .none
        for layer in liveLayers() { layer.content = content }
    }

    // MARK: - Notice

    func show(_ message: String) {
        notice = message
        announce(message)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }
}

/// A weakly held logo layer (the compositor owns it).
private struct WeakLogoLayer {
    weak var layer: LogoLayerSource?
    init(_ layer: LogoLayerSource) { self.layer = layer }
}

extension Compositor {
    /// MED-010-R5 (research MED-010-D4): adds `layer` as the top `.logo` entry of the applied stack. Kept
    /// entries keep their layers, pictures and state (CMP-002); false when no stack is applied, a logo is
    /// already there or the stack refuses it (the previous stack stays).
    @discardableResult
    func attachLogo(_ layer: LogoLayerSource) -> Bool {
        guard var stack = appliedStack,
              !stack.entries.contains(where: { (entry: LayerStackEntry) -> Bool in entry.descriptor.kind == .logo }) else { return false }
        do {
            try stack.add(LayerDescriptor(kind: .logo))
            try apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                guard entry.descriptor.kind == .logo else { throw .notReady }
                return layer
            }
        } catch {
            return false
        }
        return true
    }
}
