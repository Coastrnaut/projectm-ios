// GoldenEnvironment.swift — platform class, record policy and CI guard, OS version (QA-002-R9, R11,
// R12; spec Clarifications; research D6, D9). Plain Swift.
import Foundation

/// Goldens are kept per platform class (QA-002-R11). Physical devices have none yet (device stage).
public enum GoldenPlatformClass: String, Sendable, CaseIterable, Codable {
    case macOS = "macos"
    case iOSSimulator = "ios-simulator"

    /// The class of the running build, or nil (a physical device, Linux): comparison pending.
    public static var current: GoldenPlatformClass? {
        #if os(macOS)
        return .macOS
        #elseif targetEnvironment(simulator)
        return .iOSSimulator
        #else
        return nil
        #endif
    }
}

/// What the suite may do with goldens in this run.
public enum GoldenRecordPolicy: Sendable, Equatable {
    /// Compare only; a missing golden fails.
    case compare
    /// `GOLDEN_RECORD=1`: write missing goldens and replace failing ones.
    case record
    /// Recording was asked in a CI environment: fail and write nothing.
    case refused

    /// The environment variable that switches recording on (on the simulator pass
    /// `TEST_RUNNER_GOLDEN_RECORD=1`; xcodebuild strips the prefix).
    public static let recordVariable = "GOLDEN_RECORD"
    /// Any of these set (non-empty) means CI: recording is refused.
    public static let ciVariables = ["CI", "GITHUB_ACTIONS"]

    public static func from(environment: [String: String]) -> GoldenRecordPolicy {
        guard environment[recordVariable] == "1" else { return .compare }
        let ci = ciVariables.contains { (name: String) -> Bool in !(environment[name] ?? "").isEmpty }
        return ci ? .refused : .record
    }

    public static var current: GoldenRecordPolicy { from(environment: ProcessInfo.processInfo.environment) }
}

public enum GoldenOS {
    /// "major.minor" of the running OS (text scenes compare only on the recorded one).
    public static var currentVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }
}
