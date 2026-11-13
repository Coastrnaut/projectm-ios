// PERF-006-T03: the memory recovery event (PERF-006-R14) can be emitted from the main thread.
#if canImport(os)
import XCTest
@testable import Diagnostics

final class MemoryRecoveryLogTests: XCTestCase {
    func testEmittingARecoveryDoesNotTrap() {
        DiagnosticsLog.memoryRecovery("warning escalated=no freed 0 B 0 items []")
        DiagnosticsLog.memoryRecovery("critical escalated=yes freed 262144 B 1 items [preset warm-up context ~262144 B 1]")
    }
}
#endif
