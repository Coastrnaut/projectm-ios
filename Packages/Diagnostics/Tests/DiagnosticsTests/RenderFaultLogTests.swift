// PERF-014-T03: the render fault event (PERF-014-R13) can be emitted from the main thread.
#if canImport(os)
import XCTest
@testable import Diagnostics

final class RenderFaultLogTests: XCTestCase {
    func testEmittingARenderFaultDoesNotTrap() {
        DiagnosticsLog.renderFault("photo recovering layerPrepareFailed faults 1 recoveries 0 tick 30")
        DiagnosticsLog.renderFault("projectM placeholder presentationFailed faults 5 recoveries 0 tick 451")
    }
}
#endif
