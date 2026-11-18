// UITestPhotoLibrarySeed.swift — DEBUG only (QA-011 device automation, Batch 1). `-uitestSeedPhotoLibrary
// <name,name,…>` adds files from the app's Documents (copied there by scripts/install_test_fixtures.py) to the
// device's photo library with add-only access, so tests of the Photos picker have known pictures and clips to pick
// without a person. It asks add-only access the way the app's Save to Photos does (one iOS prompt per device,
// answered in PromptFlowDeviceTests); every run adds the files again (add-only access cannot see the library).
// Movies (.mov, .mp4, .m4v) are added as videos, everything else as photos. The `photoLibrarySeed` probe (with
// `-uitestDiagnostics`) and Documents/photo-library-seed.txt report "status=<…> added=<n> missing=<n> failed=<n>
// done=1". Not compiled into Release builds.
#if DEBUG
import Foundation
import Photos

@MainActor
@Observable
final class UITestPhotoLibrarySeed {
    static let shared = UITestPhotoLibrarySeed()
    static let argument = "-uitestSeedPhotoLibrary"
    private(set) var value = "idle"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: Self.argument), i + 1 < arguments.count,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let names = arguments[i + 1].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let present = names.map { documents.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        let missing = names.count - present.count
        value = "status=asking added=0 missing=\(missing) failed=0 done=0"
        Task { @MainActor in
            let status: PHAuthorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                self.finish("status=denied added=0 missing=\(missing) failed=\(present.count) done=1", documents)
                return
            }
            var added = 0, failed = 0
            for url in present {
                do {
                    try await PHPhotoLibrary.shared().performChanges(Self.changes(for: url))
                    added += 1
                } catch {
                    failed += 1
                }
            }
            self.finish("status=granted added=\(added) missing=\(missing) failed=\(failed) done=1", documents)
        }
    }

    private func finish(_ result: String, _ documents: URL) {
        value = result
        try? result.write(to: documents.appendingPathComponent("photo-library-seed.txt"), atomically: true, encoding: .utf8)
    }

    /// The change block, made outside the main actor (Photos runs it on its own queue; see LivePhotosSaver).
    nonisolated private static func changes(for url: URL) -> @Sendable () -> Void {
        { () -> Void in
            let video = ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = url.lastPathComponent
            PHAssetCreationRequest.forAsset().addResource(with: video ? .video : .photo, fileURL: url, options: options)
        }
    }
}
#endif
