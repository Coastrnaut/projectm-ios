// PRE-012-T01: synthetic presets and helpers for the user-preset tests. The preset text is written
// for this repository; no third-party preset is copied here.
import Foundation
import XCTest
@testable import PresetLibrary

enum UserPresetFixtures {
    /// A small valid Milkdrop preset. Sections can be replaced or extended by the tests.
    static func preset(header: String = "[preset00]",
                       settings: [String] = ["fRating=3.000000", "fDecay=0.960000", "zoom=1.010000", "rot=0.010000",
                                             "wave_r=0.600000", "wave_g=0.600000", "wave_b=0.900000"],
                       perFrame: [String] = ["wave_r = 0.5 + 0.5*sin(time*1.1);", "rot = 0.02*sin(time*0.3) + 0.01*bass;"],
                       perPixel: [String] = ["zoom = zoom + 0.02*sin(rad*6 + time);"],
                       warp: [String] = [],
                       comp: [String] = [],
                       extra: [String] = [],
                       newline: String = "\n") -> String {
        var lines = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "PSVERSION_WARP=2", "PSVERSION_COMP=2"]
        if !header.isEmpty { lines.append(header) }
        lines += settings
        lines += perFrame.enumerated().map { "per_frame_\($0.offset + 1)=\($0.element)" }
        lines += perPixel.enumerated().map { "per_pixel_\($0.offset + 1)=\($0.element)" }
        lines += warp.enumerated().map { "warp_\($0.offset + 1)=`\($0.element)" }
        lines += comp.enumerated().map { "comp_\($0.offset + 1)=`\($0.element)" }
        lines += extra
        return lines.joined(separator: newline) + newline
    }

    static let warpShader = ["shader_body", "{", "    ret = tex2D(sampler_main, uv).xyz * 0.97;", "}"]
    static let compShader = ["shader_body", "{", "    ret = tex2D(sampler_main, uv).xyz + 0.05*tex2D(sampler_noise_lq, uv).xyz;", "}"]

    static var valid: String { preset(warp: warpShader, comp: compShader) }
    static var validBytes: [UInt8] { Array(valid.utf8) }

    static func tempDirectory(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pre012-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    static func write(_ text: String, named name: String, in folder: URL) throws -> URL {
        try write(Data(text.utf8), named: name, in: folder)
    }

    @discardableResult
    static func write(_ data: Data, named name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// Every file under `directory` with its bytes: the "nothing changed" snapshot.
    static func snapshot(_ directory: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        let base = directory.resolvingSymlinksInPath().path
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.resolvingSymlinksInPath().path
            result[String(path.dropFirst(base.count))] = (try? Data(contentsOf: url)) ?? Data()
        }
        return result
    }
}

/// A scripted trial: returns the queued results in order (then `fallback`), and records what it saw.
final class FakeTrial: PresetTrialRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [PresetTrialResult]
    private let fallback: PresetTrialResult
    private var seen: [Data] = []
    /// Runs inside `run`, before the result is returned (to look at the disk mid-trial).
    var onRun: (@Sendable (Data) -> Void)?
    /// When set, `run` never returns (the app "dies" during the trial).
    var hangs = false

    init(_ results: [PresetTrialResult] = [], fallback: PresetTrialResult = .passed) {
        queue = results
        self.fallback = fallback
    }

    var calls: [Data] { lock.withLock { seen } }

    func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult {
        lock.withLock { seen.append(contents) }
        onRun?(contents)
        if hangs { try? await Task.sleep(for: .seconds(3600)) }
        return lock.withLock { queue.isEmpty ? fallback : queue.removeFirst() }
    }
}
