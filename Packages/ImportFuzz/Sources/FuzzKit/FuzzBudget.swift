// FuzzBudget.swift — how much a run may do, counted in inputs and bytes, never in time
// (QA-005-R3, R7; contract H2; research QA-005-D3, D4).
import Foundation

public struct FuzzBudget: Sendable, Equatable {
    /// Inputs per run (at least 1).
    public var inputs: Int
    /// Largest input presented to the parser.
    public var maxInputBytes: Int
    /// Bytes presented over the whole run; the run stops once it is reached.
    public var maxRunBytes: Int

    public init(inputs: Int, maxInputBytes: Int, maxRunBytes: Int? = nil) {
        self.inputs = Swift.max(inputs, 1)
        self.maxInputBytes = Swift.max(maxInputBytes, 0)
        let product: Int = self.inputs.multipliedReportingOverflow(by: Swift.max(self.maxInputBytes, 1)).overflow
            ? Int.max : self.inputs * Swift.max(self.maxInputBytes, 1)
        self.maxRunBytes = maxRunBytes ?? product
    }

    /// This budget with `inputs` replaced (the run-byte budget scales with it).
    public func withInputs(_ count: Int) -> FuzzBudget {
        FuzzBudget(inputs: count, maxInputBytes: maxInputBytes)
    }
}

/// On-demand overrides from the environment. Unset, every suite uses its fixed seed and its default
/// budget, which is what CI runs.
public struct FuzzConfiguration: Sendable, Equatable {
    /// Hard ceiling for `FUZZ_ITERATIONS`.
    public static let maximumIterations = 100_000

    /// `FUZZ_ITERATIONS`: inputs per suite, 1…100,000 (larger values are capped).
    public var iterationsOverride: Int?
    /// `FUZZ_SEED`: XOR-ed into every suite's fixed seed.
    public var seedOverride: UInt64?

    public init(iterationsOverride: Int? = nil, seedOverride: UInt64? = nil) {
        self.iterationsOverride = iterationsOverride
        self.seedOverride = seedOverride
    }

    public init(environment: [String: String]) {
        iterationsOverride = Self.parseIterations(environment["FUZZ_ITERATIONS"])
        seedOverride = Self.parseSeed(environment["FUZZ_SEED"])
    }

    /// The process's environment.
    public static var current: FuzzConfiguration { FuzzConfiguration(environment: ProcessInfo.processInfo.environment) }

    /// Zero, negative, empty or non-numeric → nil (the default is used); above the ceiling → the ceiling.
    public static func parseIterations(_ text: String?) -> Int? {
        guard let raw = text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              raw.utf8.allSatisfy({ (b: UInt8) -> Bool in b >= 0x30 && b <= 0x39 }) else { return nil }
        guard let value = Int(raw) else { return maximumIterations }   // too many digits
        guard value > 0 else { return nil }
        return Swift.min(value, maximumIterations)
    }

    /// Decimal or `0x` hexadecimal; anything else → nil.
    public static func parseSeed(_ text: String?) -> UInt64? {
        guard let raw = text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("0x") { return UInt64(lower.dropFirst(2).replacingOccurrences(of: "_", with: ""), radix: 16) }
        return UInt64(raw)
    }

    /// The budget a suite uses: its default, or `FUZZ_ITERATIONS` divided by `divisor` (at least 1).
    public func budget(_ base: FuzzBudget, divisor: Int = 1) -> FuzzBudget {
        guard let n = iterationsOverride else { return base }
        return base.withInputs(Swift.max(n / Swift.max(divisor, 1), 1))
    }

    /// The seed a suite uses.
    public func seed(_ base: UInt64) -> UInt64 { base ^ (seedOverride ?? 0) }
}
