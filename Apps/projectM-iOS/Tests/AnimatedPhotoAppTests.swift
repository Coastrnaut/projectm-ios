// AnimatedPhotoAppTests.swift — MED-008-T09, T10 (app): an animated GIF picked as the photo is stored as an animated PNG
// in the photo folder (same `.png` payload kind, so scenes, archives and relinking are unchanged), passes the scene
// archive's content check, and plays on a real Photo visual's layer; VoiceOver names the animation. No wall clock.
import Compositor
import Foundation
import ImageIO
import ImageLayer
import Metal
import SceneArchive
import UniformTypeIdentifiers
import XCTest
@testable import projectM_iOS

@MainActor
final class AnimatedPhotoAppTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() async throws {
        suite = "AnimatedPhotoAppTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED008-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    /// A 3-frame 24 × 24 GIF (solid frames, 100 ms each) written with ImageIO.
    private func pickedGIF() throws -> URL {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, 3, nil))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for i in 0..<3 {
            let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96, space: space,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: CGFloat(i) / 3, green: 0.3, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            let frame: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), frame as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let url = directory.appendingPathComponent("picked.gif")
        try (data as Data).write(to: url)
        return url
    }

    /// MED-008-S4, S5: the stored copy is an animated `.png`, and a scene archive accepts it as a photo asset.
    func testAnImportedGIFIsStoredAsAnAnimatedPNGThatScenesAccept() throws {
        let store = PhotoStore(directory: directory.appendingPathComponent("Photos"), defaults: defaults)
        let stored = try store.importImage(at: try pickedGIF())
        XCTAssertEqual(stored.url.pathExtension, "png", "the photo asset kind and extension are unchanged")
        XCTAssertEqual(store.current(), stored)
        let data = try Data(contentsOf: stored.url)
        let facts = try XCTUnwrap(AnimatedImageProbe.facts(data))
        XCTAssertEqual(facts.frameCount, 3)
        XCTAssertNoThrow(try SceneArchiveContentCheck.check(data, path: "assets/photo.png", type: .photo, fileExtension: "png",
                                                             limits: .standard))
    }

    /// MED-008-R6, R7, R10, R12: the stored animation plays on a real Photo visual's layer.
    func testThePhotoVisualPlaysTheStoredAnimation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let store = PhotoStore(directory: directory.appendingPathComponent("Photos"), defaults: defaults)
        let stored = try store.importImage(at: try pickedGIF())
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        host.content = .file(stored.url)
        host.photo.waitUntilLoaded()
        XCTAssertEqual(host.photo.state, .ready(width: 24, height: 24))
        XCTAssertEqual(host.photo.animationFrameCount, 3)
        XCTAssertTrue(host.photo.renderDependencies.time, "an animation renders every frame")
        XCTAssertTrue(host.photo.isAnimating, "the render side holds the animation")
        XCTAssertEqual(PhotoVisualHost.accessibilityValue(host.photo.state, frames: host.photo.animationFrameCount),
                       "Animated photo 24 × 24, 3 frames")
        XCTAssertEqual(PhotoVisualHost.accessibilityValue(.ready(width: 64, height: 48), frames: 0), "Photo 64 × 48")
        host.photo.reduceMotion = true
        XCTAssertFalse(host.photo.isAnimating, "Reduce Motion holds the first frame")
        XCTAssertFalse(host.photo.renderDependencies.time)
    }
}
