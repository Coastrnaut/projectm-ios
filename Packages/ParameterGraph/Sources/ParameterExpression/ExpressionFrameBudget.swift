// ExpressionFrameBudget.swift — the per-frame budget of formula evaluation (SHD-010-R2 to R4, R8;
// contract specs/047-shd-010-expression-sandbox-budgets/contracts/expression-budgets.md B1, B2).
//
// The formulas evaluated in one frame are collected in an `ExpressionFrameSet` off the frame loop:
// admission checks, in order, that the formula was compiled under limits no looser than the
// budget's, that the set has room for one more formula, and that its static cost fits the frame's
// remaining cost. The set hands the frame loop an immutable `ExpressionFrameSnapshot` whose only
// operation is evaluation into a caller buffer. Neither type accepts source text, so parsing and
// compiling cannot happen on the frame path; and since every instruction runs exactly once, a
// snapshot's evaluation does exactly `operationCost` weighted instructions, with no clock and no heap.

public struct ExpressionFrameBudget: Sendable, Hashable {
    /// Formulas evaluated per frame.
    public var maximumExpressions: Int
    /// The total static cost of those formulas (inclusive).
    public var maximumOperationCost: Int
    /// Each admitted formula's own limits must be field by field at most these.
    public var expressionLimits: ExpressionLimits

    public init(maximumExpressions: Int = 32, maximumOperationCost: Int = 2048,
                expressionLimits: ExpressionLimits = .standard) {
        self.maximumExpressions = maximumExpressions
        self.maximumOperationCost = maximumOperationCost
        self.expressionLimits = expressionLimits
    }

    /// 32 formulas (MOD-002's `AudioFeatureModulator.maximumBindings`), cost 2,048 (eight formulas at
    /// the per-formula maximum of 256), per-formula limits `ExpressionLimits.standard`.
    public static let standard = ExpressionFrameBudget()
}

/// Why the frame set refused a formula (contract B2). The formula itself is valid, so there is no
/// source position.
public struct ExpressionBudgetError: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Reason: Sendable, Hashable {
        case looserLimit(ExpressionLimits.Field, value: Int, standard: Int)
        case tooManyExpressions(limit: Int)
        case costOverBudget(cost: Int, total: Int, limit: Int, used: Int)
    }

    public var reason: Reason

    public init(_ reason: Reason) { self.reason = reason }

    public var description: String {
        switch reason {
        case let .looserLimit(field, value, standard):
            "the formula was compiled with \(field.label) limit of \(value); the standard limit is \(standard)"
        case let .tooManyExpressions(limit):
            "the frame already evaluates \(limit) formulas; at most \(limit) are allowed"
        case let .costOverBudget(cost, total, limit, used):
            "a formula of cost \(cost) would bring the frame to \(total); at most \(limit) is allowed (\(used) used)"
        }
    }
}

/// The formulas admitted for evaluation every frame. Edit it off the frame loop; give the frame loop
/// its `snapshot`.
public struct ExpressionFrameSet: Sendable {
    /// Identifies one admission; issued from 1 upward and never reused within one set.
    public struct Handle: Sendable, Hashable, Comparable {
        public let rawValue: UInt64

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let budget: ExpressionFrameBudget
    public private(set) var usedCost = 0
    private var expressions: [CompiledExpression] = []
    public private(set) var handles: [Handle] = []
    private var nextHandle: UInt64 = 1

    public init(budget: ExpressionFrameBudget = .standard) {
        self.budget = budget
    }

    public var count: Int { expressions.count }

    /// Admits a compiled formula, or throws why not (loosened limits, then count, then cost); the
    /// set is unchanged when it throws.
    public mutating func admit(_ expression: CompiledExpression) throws(ExpressionBudgetError) -> Handle {
        if let field = expression.limits.firstLooserField(than: budget.expressionLimits) {
            throw ExpressionBudgetError(.looserLimit(field, value: expression.limits.value(of: field),
                                                     standard: budget.expressionLimits.value(of: field)))
        }
        if expressions.count >= budget.maximumExpressions {
            throw ExpressionBudgetError(.tooManyExpressions(limit: budget.maximumExpressions))
        }
        let total = usedCost + expression.operationCost
        if total > budget.maximumOperationCost {
            throw ExpressionBudgetError(.costOverBudget(cost: expression.operationCost, total: total,
                                                        limit: budget.maximumOperationCost, used: usedCost))
        }
        let handle = Handle(rawValue: nextHandle)
        nextHandle += 1
        expressions.append(expression)
        handles.append(handle)
        usedCost = total
        return handle
    }

    /// Removes an admitted formula and frees its cost; false when the handle is unknown or already
    /// removed.
    @discardableResult
    public mutating func remove(_ handle: Handle) -> Bool {
        guard let index = handles.firstIndex(of: handle) else { return false }
        usedCost -= expressions[index].operationCost
        expressions.remove(at: index)
        handles.remove(at: index)
        return true
    }

    /// The admitted formulas, in admission order, for the frame loop.
    public var snapshot: ExpressionFrameSnapshot {
        ExpressionFrameSnapshot(expressions: expressions, handles: handles, operationCost: usedCost)
    }
}

/// An immutable set of admitted formulas; its only operation is evaluation (contract B1).
public struct ExpressionFrameSnapshot: Sendable {
    public let expressions: [CompiledExpression]
    public let handles: [ExpressionFrameSet.Handle]
    /// The total static cost: the weighted instructions one `evaluate` runs (≤ the budget).
    public let operationCost: Int

    /// Evaluates the formulas in admission order into `results` (result `i` belongs to `handles[i]`);
    /// evaluates `min(expressions.count, results.count)` formulas and returns that number. No heap
    /// allocation, no clock.
    public func evaluate(_ inputs: ExpressionInputs, into results: UnsafeMutableBufferPointer<Double>) -> Int {
        let n = Swift.min(expressions.count, results.count)
        for i in 0..<n {
            results[i] = expressions[i].evaluate(inputs)
        }
        return n
    }
}
