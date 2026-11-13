// FuzzCampaign.swift — one suite's run: inputs derived from (seed, iteration), caps and budgets, the
// work bound ("hang" without a clock) and the failure report (QA-005-R1, R3, R4, R8; contract H1-H4).

/// One generated input and how it was made (everything needed to rebuild it).
public struct FuzzInput: Sendable, CustomStringConvertible {
    public let bytes: [UInt8]
    public let iteration: Int
    public let seed: UInt64
    /// Strategies applied in order; empty for a corpus item presented unchanged.
    public let strategies: [FuzzMutation]
    /// Index of the corpus item mutated, or nil for random bytes.
    public let baseIndex: Int?

    public var description: String {
        let names = strategies.map { (m: FuzzMutation) -> String in m.rawValue }.joined(separator: ",")
        let base = baseIndex.map { (i: Int) -> String in String(i) } ?? "random"
        return "seed=0x\(String(seed, radix: 16)) iteration=\(iteration) strategies=[\(names)] base=\(base) size=\(bytes.count)"
    }
}

/// What a parser did with one input.
public struct FuzzOutcome: Sendable, Equatable {
    public enum Kind: String, Sendable { case accepted, refused }
    public var kind: Kind
    /// The parser's own work counter, when it has one (checked against the campaign's work bound).
    public var work: Int?
    /// A broken invariant, described for the report.
    public var violation: String?

    public static func accepted(work: Int? = nil, violation: String? = nil) -> FuzzOutcome {
        FuzzOutcome(kind: .accepted, work: work, violation: violation)
    }

    public static func refused(work: Int? = nil, violation: String? = nil) -> FuzzOutcome {
        FuzzOutcome(kind: .refused, work: work, violation: violation)
    }
}

public struct FuzzReport: Sendable, CustomStringConvertible {
    public let name: String
    public internal(set) var inputs = 0
    public internal(set) var bytes = 0
    public internal(set) var accepted = 0
    public internal(set) var refused = 0
    /// FNV-1a 64 over every input's length (8 bytes, little-endian) and bytes (contract H1).
    public internal(set) var digest: UInt64 = 0xCBF2_9CE4_8422_2325
    public internal(set) var violations: [String] = []
    public internal(set) var strategyCounts: [FuzzMutation: Int] = [:]
    /// Largest work any input reported.
    public internal(set) var maxWork = 0

    init(name: String) { self.name = name }

    mutating func absorb(_ input: [UInt8]) {
        var n = UInt64(input.count)
        for _ in 0..<8 {
            digest = (digest ^ (n & 0xFF)) &* 0x0000_0100_0000_01B3
            n >>= 8
        }
        for b in input { digest = (digest ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
    }

    public var description: String {
        "QA-005 \(name): inputs=\(inputs) bytes=\(bytes) accepted=\(accepted) refused=\(refused) maxWork=\(maxWork) "
            + "digest=0x\(String(digest, radix: 16)) violations=\(violations.count)"
    }
}

public struct FuzzCampaign: Sendable {
    public let name: String
    public let seed: UInt64
    public let budget: FuzzBudget
    public let strategies: [FuzzMutation]
    public let corpus: [[UInt8]]
    /// Largest acceptable work for an input of the given size (nil: the parser reports no work).
    public let workBound: (@Sendable (Int) -> Int)?
    /// Extra format-aware strategies supplied by the suite (for example re-zipping an archive).
    public let customMutations: [@Sendable ([UInt8], inout FuzzRandom, Int) -> [UInt8]]

    /// Applies `FuzzConfiguration` (seed and budget overrides) when `configuration` is given.
    public init(name: String, seed: UInt64, budget: FuzzBudget, strategies: [FuzzMutation], corpus: [[UInt8]],
                configuration: FuzzConfiguration = .current, budgetDivisor: Int = 1,
                workBound: (@Sendable (Int) -> Int)? = nil,
                customMutations: [@Sendable ([UInt8], inout FuzzRandom, Int) -> [UInt8]] = []) {
        self.name = name
        self.seed = configuration.seed(seed)
        self.budget = configuration.budget(budget, divisor: budgetDivisor)
        self.strategies = strategies.isEmpty ? FuzzMutation.generic : strategies
        self.corpus = corpus
        self.workBound = workBound
        self.customMutations = customMutations
    }

    /// Input `iteration`: the corpus items first, unchanged; then 1-4 stacked mutations of a corpus
    /// item (or, one in 16, of random bytes). Depends only on (seed, iteration).
    public func input(_ iteration: Int) -> FuzzInput {
        let cap = budget.maxInputBytes
        if iteration < corpus.count {
            return FuzzInput(bytes: Array(corpus[iteration].prefix(cap)), iteration: iteration, seed: seed, strategies: [], baseIndex: iteration)
        }
        var rng = FuzzRandom(state: FuzzRandom.mix(seed) &+ UInt64(iteration))
        var base: Int? = nil
        var bytes: [UInt8]
        if corpus.isEmpty || rng.chance(oneIn: 16) {
            bytes = rng.bytes(count: rng.below(Swift.min(cap, 512) + 1))
        } else {
            let i = rng.below(corpus.count)
            base = i
            bytes = Array(corpus[i].prefix(cap))
        }
        var applied: [FuzzMutation] = []
        let steps = rng.pick(1...4)
        for _ in 0..<steps {
            if !customMutations.isEmpty, rng.chance(oneIn: 3) {
                let custom = customMutations[rng.below(customMutations.count)]
                bytes = custom(bytes, &rng, cap)
                if bytes.count > cap { bytes = Array(bytes.prefix(cap)) }
                continue
            }
            let strategy = rng.element(of: strategies)
            let other = corpus.isEmpty ? [] : corpus[rng.below(corpus.count)]
            bytes = strategy.apply(to: bytes, other: other, rng: &rng, cap: cap)
            applied.append(strategy)
        }
        return FuzzInput(bytes: bytes, iteration: iteration, seed: seed, strategies: applied, baseIndex: base)
    }

    /// Runs the suite. The body must return a typed outcome for every input; a trap in the parser ends
    /// the test process (the crash signal). Stops at the input budget or the run-byte budget.
    public func run(_ body: (FuzzInput) -> FuzzOutcome) -> FuzzReport {
        var report = FuzzReport(name: name)
        var iteration = 0
        while report.inputs < budget.inputs, report.bytes < budget.maxRunBytes {
            let input = input(iteration)
            iteration += 1
            report.inputs += 1
            report.bytes += input.bytes.count
            report.absorb(input.bytes)
            for s in input.strategies { report.strategyCounts[s, default: 0] += 1 }
            let outcome = body(input)
            switch outcome.kind {
            case .accepted: report.accepted += 1
            case .refused: report.refused += 1
            }
            if let work = outcome.work {
                report.maxWork = Swift.max(report.maxWork, work)
                if let bound = workBound?(input.bytes.count), work > bound {
                    report.violations.append("\(name) \(input): hang bound: work \(work) > \(bound)")
                }
            }
            if let violation = outcome.violation {
                report.violations.append("\(name) \(input): \(violation)")
            }
        }
        return report
    }

    /// Async variant for parsers behind an actor (user preset import).
    public func runAsync(_ body: (FuzzInput) async -> FuzzOutcome) async -> FuzzReport {
        var outcomes: [Int: FuzzOutcome] = [:]
        var inputs: [FuzzInput] = []
        var total = 0
        var iteration = 0
        while inputs.count < budget.inputs, total < budget.maxRunBytes {
            let next = input(iteration)
            iteration += 1
            total += next.bytes.count
            inputs.append(next)
        }
        for item in inputs { outcomes[item.iteration] = await body(item) }
        return run { (item: FuzzInput) -> FuzzOutcome in outcomes[item.iteration] ?? .refused(violation: "no outcome") }
    }
}
