// LogoStoreTests.swift — MED-010-T13, T16: the stored logo (MED-010-R2, R3, R9; S1, S5) and the coordinator's
// placement and layers. Each test uses its own temporary folder and UserDefaults suite; fixtures are made with
// ImageIO. "Relaunch" is a new store and coordinator on the same folder and defaults.
import CoreGraphics
import Foundation
import ImageIO
import ImageLayer
import LocalPortability
import Metal
import UniformTypeIdentifiers
import XCTest
import Compositor
@testable import projectM_iOS

/// The MED-010 fixture: 64 × 64, colour (220, 40, 200), alpha x·255/63 in the top 46 rows, transparent below.
enum LogoTestFixture {
    static let size = 64
    static let opaqueRows = 46

    static func alpha(x: Int, y: Int) -> UInt8 {
        guard y < opaqueRows else { return 0 }
        return UInt8((x * 255 + 31) / 63)
    }

    /// Straight-alpha RGBA bytes of the fixture.
    static func pixels() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let a: UInt8 = alpha(x: x, y: y)
                guard a > 0 else { continue }
                let i: Int = (y * size + x) * 4
                bytes[i] = 220; bytes[i + 1] = 40; bytes[i + 2] = 200; bytes[i + 3] = a
            }
        }
        return bytes
    }

    static func encode(_ bytes: [UInt8], width: Int, height: Int, alpha: Bool, type: UTType) throws -> Data {
        let info: CGImageAlphaInfo = alpha ? .last : .noneSkipLast
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                          space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                          bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                                          provider: try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)), decode: nil,
                                          shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func png() throws -> Data { try encode(pixels(), width: size, height: size, alpha: true, type: .png) }

    /// Decoded alpha of a stored copy, compared with the fixture: the largest difference (in 1/255 steps).
    static func worstAlphaError(of url: URL) throws -> Int {
        let decoded = try ImageIODecoder().decode(try Data(contentsOf: url), limits: LogoImport.limits)
        XCTAssertEqual(decoded.width, size)
        XCTAssertEqual(decoded.height, size)
        var worst = 0
        for y in 0..<size {
            for x in 0..<size {
                let stored: Int = Int(decoded.pixels[(y * size + x) * 4 + 3])
                worst = max(worst, abs(stored - Int(alpha(x: x, y: y))))
            }
        }
        return worst
    }
}

@MainActor
final class LogoStoreTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        var photosFolder: URL { root.appendingPathComponent("Photos") }

        func photos() -> PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        func logos() -> LogoStore { LogoStore(photos: photos()) }

        func write(_ data: Data, _ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        func payloads() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: photosFolder.path)) ?? [])
                .filter { (name: String) -> Bool in name != ContentAddressedMediaFolder.registryName }.sorted()
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LogoStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "LogoStoreTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    /// S1 (the import acceptance): the stored copy is PNG and its alpha matches the fixture within 1/255.
    func testImportKeepsAlphaWithinOneStep() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let stored = try sandbox.logos().importLogo(at: try sandbox.write(try LogoTestFixture.png(), "picked.png"))
        XCTAssertEqual(stored.url.pathExtension, "png")
        XCTAssertEqual(sandbox.defaults.string(forKey: LogoStore.idKey), stored.id.uuidString)
        XCTAssertLessThanOrEqual(try LogoTestFixture.worstAlphaError(of: stored.url), 1, "S1: alpha within 1/255")
        let decoded = try ImageIODecoder().decode(try Data(contentsOf: stored.url), limits: LogoImport.limits)
        let bottom: [UInt8] = (0..<LogoTestFixture.size).map { (x: Int) -> UInt8 in decoded.pixels[((LogoTestFixture.size - 1) * LogoTestFixture.size + x) * 4 + 3] }
        XCTAssertEqual(Set(bottom), [0], "the transparent region stays fully transparent")
        XCTAssertEqual(sandbox.logos().current(), stored, "relaunch keeps the logo")
    }

    func testOpaqueAndJPEGInputsAreStoredAsPNG() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let opaque = [UInt8](repeating: 200, count: 16 * 16 * 4)
        let jpeg = try LogoTestFixture.encode(opaque, width: 16, height: 16, alpha: false, type: .jpeg)
        let stored = try sandbox.logos().importLogo(at: try sandbox.write(jpeg, "picked.jpg"))
        XCTAssertEqual(stored.url.pathExtension, "png", "a logo is always PNG")
    }

    func testOversizedFilesAndPicturesAreRefusedAndTheLogoStays() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.logos().importLogo(at: try sandbox.write(try LogoTestFixture.png(), "picked.png"))
        let big = try sandbox.write(Data(repeating: 0x41, count: 10 * 1024 * 1024 + 1), "big.png")
        XCTAssertThrowsError(try sandbox.logos().importLogo(at: big)) { (error: any Error) in
            XCTAssertEqual(error as? ImageImportError, .tooLarge)
        }
        // 4097 × 4097 stated in a PNG header: refused before decoding.
        let huge = try sandbox.write(Data(MediaFixtureHeader.png(width: 4097, height: 4097)), "huge.png")
        XCTAssertThrowsError(try sandbox.logos().importLogo(at: huge)) { (error: any Error) in
            XCTAssertEqual(error as? ImageImportError, .tooManyPixels)
        }
        XCTAssertEqual(sandbox.logos().current(), first, "a refused import keeps the logo")
        XCTAssertTrue(LogoImport.message(for: .tooManyPixels).contains("4096"))
    }

    /// S5: one payload for equal pictures; the photo, slides and logo never release each other.
    func testDedupAndProtectionBetweenPhotoAndLogo() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let picked = try sandbox.write(try LogoTestFixture.png(), "picked.png")
        let logo = try sandbox.logos().importLogo(at: picked)
        _ = try sandbox.logos().importLogo(at: picked)
        XCTAssertEqual(sandbox.payloads().count, 1, "the same logo twice: one payload")
        let photo = try sandbox.photos().importImage(at: picked)
        XCTAssertEqual(sandbox.payloads().count, 1, "a photo equal to the logo shares its payload")
        sandbox.photos().remove()
        XCTAssertNotNil(sandbox.logos().current(), "Remove Photo keeps the logo")
        XCTAssertEqual(sandbox.payloads().count, 1)
        let other = try sandbox.write(try LogoTestFixture.encode([UInt8](repeating: 90, count: 8 * 8 * 4), width: 8, height: 8,
                                                                 alpha: false, type: .png), "other.png")
        _ = try sandbox.photos().importImage(at: other)
        _ = try sandbox.photos().importImage(at: picked)   // a new photo again sharing the logo's payload, then replaced
        _ = try sandbox.photos().importImage(at: other)
        XCTAssertNotNil(sandbox.logos().current(), "new photos keep the logo")
        XCTAssertNotNil(sandbox.photos().existingFile(for: logo.id) ?? sandbox.logos().current()?.url)
        sandbox.logos().remove()
        XCTAssertNil(sandbox.logos().current())
        XCTAssertNotNil(sandbox.photos().current(), "Remove Logo keeps the photo")
        XCTAssertEqual(sandbox.payloads().count, 1, "only the photo's payload is left")
        _ = photo
    }

    /// T16: placement setters persist, reach an attached layer, and survive a relaunch.
    func testPlacementPersistsAndReachesAttachedLayers() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        var spoken: [String] = []
        let coordinator = LogoCoordinator(store: sandbox.logos(), announce: { (text: String) in spoken.append(text) })
        XCTAssertEqual(coordinator.placement, .default)
        coordinator.setCorner(.topLeft)
        coordinator.setSize(0.3)
        coordinator.setMargin(0.1)
        coordinator.setOpacity(0.6)
        let expected = LogoPlacement(corner: .topLeft, size: 0.3, margin: 0.1, opacity: 0.6)
        XCTAssertEqual(coordinator.placement, expected)
        XCTAssertEqual(LogoCoordinator(store: sandbox.logos()).placement, expected, "relaunch keeps the placement")
        XCTAssertEqual(spoken, ["Logo position: Top left."])
        coordinator.setPlacement(.default)
        XCTAssertNil(sandbox.defaults.object(forKey: LogoStore.placementKey), "the default removes the key")
    }

    /// T16, MED-010-R5: attaching puts the logo layer on top of a compositor's stack; placement and the logo
    /// itself reach every attached layer.
    func testAttachAddsTheTopLayerAndPushesChanges() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let coordinator = LogoCoordinator(store: sandbox.logos())
        let compositor = try Compositor(device: device)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .circularSpectrum))
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in BlankLayer() }
        let layer = try XCTUnwrap(coordinator.attach(to: compositor))
        XCTAssertEqual(compositor.appliedStack?.entries.last?.descriptor.kind, .logo, "the logo is the top layer")
        XCTAssertNil(coordinator.attach(to: compositor), "one logo layer per compositor")
        XCTAssertEqual(layer.content, .none)
        coordinator.setOpacity(0.4)
        XCTAssertEqual(layer.placement.opacity, 0.4)
        coordinator.importNow(at: try sandbox.write(try LogoTestFixture.png(), "picked.png"))
        XCTAssertEqual(layer.content, .file(try XCTUnwrap(coordinator.logo?.url)))
        coordinator.remove()
        XCTAssertEqual(layer.content, .none)
    }
}

/// A PNG whose header states `width` × `height` (MED-014's sniffer refuses it before decoding).
enum MediaFixtureHeader {
    static func png(width: Int, height: Int) -> [UInt8] {
        func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ name: String, _ data: [UInt8]) -> [UInt8] {
            let type: [UInt8] = Array(name.utf8)
            return be32(data.count) + type + data + be32(Int(crc32(type + data)))
        }
        let ihdr: [UInt8] = be32(width) + be32(height) + [8, 6, 0, 0, 0]
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return signature + chunk("IHDR", ihdr) + chunk("IDAT", [0x78, 0x01, 0x01, 0x00, 0x00]) + chunk("IEND", [])
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return c ^ 0xFFFF_FFFF
    }
}

/// A layer that draws nothing (the stack under the logo in `testAttachAddsTheTopLayerAndPushesChanges`).
private final class BlankLayer: LayerSource {
    let layerName = "blank"
    let fallback = LayerFallback.transparent
    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}
    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) { throw .notReady }
}
