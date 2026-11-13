// GoldenDecision.swift — what the suite does with one capture (QA-002 contract G4; R9-R12). A plain
// function so the whole table is tested on Linux; the GPU suite only executes the verdict.

public enum GoldenVerdict: Sendable, Equatable {
    /// Compared and passed (or kept under record because it still passes).
    case pass(String)
    /// The test fails with this message (diff artifacts are written when a comparison failed).
    case fail(String)
    /// Record mode: write this golden and its manifest entry.
    case write(String)
    /// Rendered but not compared (an OS-sensitive scene on another OS version).
    case notCompared(String)
    /// No platform class (a physical device): comparison pending the device stage.
    case pending(String)

    public var isFailure: Bool { if case .fail = self { true } else { false } }
}

public enum GoldenDecision {
    /// - Parameters:
    ///   - platform: the running class, nil on a physical device.
    ///   - comparison: nil when no golden exists.
    ///   - recordedOS: the class manifest's `recordedOS` (nil when there is no manifest).
    public static func decide(capture: String, platform: GoldenPlatformClass?, policy: GoldenRecordPolicy,
                              comparison: GoldenComparisonResult?, osSensitive: Bool, recordedOS: String?,
                              currentOS: String) -> GoldenVerdict {
        guard platform != nil else {
            return .pending("\(capture): no golden platform class on this device; comparison pending the device stage (QA-011)")
        }
        if policy == .refused {
            return .fail("\(capture): GOLDEN_RECORD=1 is refused in CI (CI or GITHUB_ACTIONS is set); nothing was written")
        }
        guard let comparison else {
            if policy == .record { return .write("\(capture): recorded (no golden yet)") }
            return .fail("\(capture): missing golden; record it on purpose with GOLDEN_RECORD=1 (see Packages/RenderGoldens/README.md)")
        }
        if osSensitive, policy == .compare, let recordedOS, recordedOS != currentOS {
            return .notCompared("\(capture): text scene recorded on OS \(recordedOS), running \(currentOS); rendered, not compared")
        }
        if comparison.passed { return .pass("\(capture): \(comparison.summary)") }
        if policy == .record { return .write("\(capture): re-recorded (\(comparison.summary))") }
        return .fail("\(capture): \(comparison.summary)")
    }
}
