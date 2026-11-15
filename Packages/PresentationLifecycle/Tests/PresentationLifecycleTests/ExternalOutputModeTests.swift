// ExternalOutputModeTests.swift — OUT-006-T02: the output layer routing table and the stored mode.
import PresentationLifecycle
import XCTest

final class ExternalOutputModeTests: XCTestCase {
    func testTheDeviceShowsEveryLayerClassInBothModes() {
        for mode in ExternalOutputMode.allCases {
            for layerClass in OutputLayerClass.allCases {
                XCTAssertTrue(OutputLayerRouting.includes(layerClass, external: false, mode: mode), "\(layerClass) \(mode)")
            }
            XCTAssertTrue(OutputLayerRouting.routesSceneOverlays(target: .device, mode: mode))
        }
    }

    func testTheExternalOutputGetsTheSceneOrTheCleanVariantAndNeverTheInterface() {
        XCTAssertTrue(OutputLayerRouting.includes(.visual, external: true, mode: .sameScene))
        XCTAssertTrue(OutputLayerRouting.includes(.sceneOverlay, external: true, mode: .sameScene))
        XCTAssertFalse(OutputLayerRouting.includes(.interface, external: true, mode: .sameScene))
        XCTAssertTrue(OutputLayerRouting.includes(.visual, external: true, mode: .clean))
        XCTAssertFalse(OutputLayerRouting.includes(.sceneOverlay, external: true, mode: .clean))
        XCTAssertFalse(OutputLayerRouting.includes(.interface, external: true, mode: .clean))
        XCTAssertTrue(OutputLayerRouting.routesSceneOverlays(target: .external(id: "a"), mode: .sameScene))
        XCTAssertFalse(OutputLayerRouting.routesSceneOverlays(target: .external(id: "a"), mode: .clean))
    }

    func testStoredValuesReadSafely() {
        XCTAssertEqual(ExternalOutputMode.default, .sameScene)
        XCTAssertEqual(ExternalOutputMode(stored: nil), .sameScene)
        XCTAssertEqual(ExternalOutputMode(stored: "mirror"), .sameScene, "unknown → Same scene")
        XCTAssertEqual(ExternalOutputMode(stored: "clean"), .clean)
        XCTAssertEqual(ExternalOutputMode(stored: "sameScene"), .sameScene)
    }
}
