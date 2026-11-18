// DeviceGoldens.swift — QA-003-T17 (QA-011 Batch 2): goldens for a physical device, kept per device model.
//
// A physical device has no `GoldenPlatformClass` (comparison "pending the device stage"), and its test bundle is
// read-only. So the suite's device path is separate from the platform classes, which every generator suite iterates:
// * `RECORD_DEVICE_GOLDENS=1` (on xcodebuild `TEST_RUNNER_RECORD_DEVICE_GOLDENS=1`; refused with CI set) attaches one
//   JSON per capture (kind `projectM-iOS.deviceGolden`: class, manifest entry, PNG in base64).
//   `scripts/import_device_goldens.py` turns the exported attachments into `Goldens/<class>/` for a commit.
// * Without it, a bundled `Goldens/<class>/manifest.json` (the device test bundle copies the Goldens folder) is
//   compared with the golden tolerance; no folder for this model keeps today's "pending".
// The class is the device model ("ios-device-iphone15-4" on D1): the same GPU and OS render the same pixels.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Foundation
import GoldenImages
import SceneRenderHarness
import XCTest

enum DeviceGoldens {
    static let recordVariable = "RECORD_DEVICE_GOLDENS"
    static let kind = "projectM-iOS.deviceGolden"

    /// "ios-device-" + the model identifier, lowercased, "," as "-".
    static func className(model: String) -> String {
        "ios-device-" + model.lowercased().replacingOccurrences(of: ",", with: "-")
    }

    static var currentClass: String {
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { (raw: UnsafeRawBufferPointer) -> String in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return className(model: model)
    }

    /// Recording asked for and not in CI (the same CI guard as `GOLDEN_RECORD`).
    static var isRecording: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment[recordVariable] == "1" else { return false }
        return !GoldenRecordPolicy.ciVariables.contains { (name: String) -> Bool in !(environment[name] ?? "").isEmpty }
    }

    static var recordRefused: Bool {
        ProcessInfo.processInfo.environment[recordVariable] == "1" && !isRecording
    }

    static var folder: URL { GoldenPaths.goldens.appendingPathComponent(currentClass, isDirectory: true) }

    static func manifest() -> GoldenManifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(GoldenManifest.fileName)) else { return nil }
        return try? GoldenManifest.decode(data)
    }

    /// One capture on a physical device: recorded (attached), compared, or pending.
    static func check(capture: String, scene: String, resolution: GoldenResolution, frame: Int, actual: GoldenImage,
                      osSensitive: Bool, gpu: String, test: XCTestCase) {
        if recordRefused {
            return XCTFail("\(capture): \(recordVariable)=1 is refused in CI (CI or GITHUB_ACTIONS is set)")
        }
        if isRecording {
            do {
                let png = try GoldenPNG.encode(actual)
                guard GoldenPNG.decode(png) == actual else { return XCTFail("\(capture): PNG does not round-trip") }
                let file = GoldenSceneCatalog.goldenFileName(scene: scene, resolution: resolution, frame: frame)
                let entry = GoldenManifestEntry(scene: scene, frame: frame, width: resolution.width, height: resolution.height,
                                                file: file, pixelSHA256: actual.pixelSHA256,
                                                fileSHA256: GoldenSHA256.hex([UInt8](png)), osSensitive: osSensitive)
                let body: [String: Any] = [
                    "kind": kind, "goldenClass": currentClass, "recordedOS": GoldenOS.currentVersion, "recordedGPU": gpu,
                    "entry": ["scene": entry.scene, "frame": entry.frame, "width": entry.width, "height": entry.height,
                              "file": entry.file, "pixelSHA256": entry.pixelSHA256, "fileSHA256": entry.fileSHA256,
                              "osSensitive": entry.osSensitive],
                    "png": png.base64EncodedString(),
                ]
                let json = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
                attachment.name = "device-golden-\(capture).json"
                attachment.lifetime = .keepAlways
                test.add(attachment)
                print("QA-003 device golden: \(capture) recorded for \(currentClass) (attachment)")
            } catch {
                XCTFail("\(capture): device golden not recorded: \(error)")
            }
            return
        }
        guard let manifest = manifest() else {
            print("QA-003 device golden: \(capture): no goldens for \(currentClass) yet; record them with "
                  + "TEST_RUNNER_\(recordVariable)=1 (pending)")
            return
        }
        guard let entry = manifest.entry(scene: scene, width: resolution.width, frame: frame),
              let data = try? Data(contentsOf: folder.appendingPathComponent(entry.file)), let expected = GoldenPNG.decode(data) else {
            return XCTFail("\(capture): missing from the \(currentClass) goldens; record them again with \(recordVariable)=1")
        }
        if osSensitive, manifest.recordedOS != GoldenOS.currentVersion {
            return print("QA-003 device golden: \(capture): recorded on \(manifest.recordedOS), running \(GoldenOS.currentVersion); "
                         + "rendered, not compared")
        }
        let comparison = GoldenComparison.compare(expected: expected, actual: actual, tolerance: .golden)
        if comparison.passed {
            print("QA-003 device golden: \(capture) [\(currentClass)]: \(comparison.summary)")
            return
        }
        for (name, image) in [("expected", expected), ("actual", actual),
                              ("diff", GoldenDiffImage.make(expected: expected, actual: actual, tolerance: .golden))] {
            guard let png = try? GoldenPNG.encode(image) else { continue }
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "\(capture) \(name)"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
        XCTFail("\(capture) [\(currentClass)]: \(comparison.summary)")
    }
}
#endif
