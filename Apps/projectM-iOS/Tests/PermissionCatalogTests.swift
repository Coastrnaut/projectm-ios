// FILE-013-T02 (specs/078-file-013-privacy-permission-audit): the permission catalog.
// * Every framework status maps to the expected PermissionState (injected statuses, FILE-013-R2, R5).
// * Denied and restricted give the expected notice text and Open Settings for all four permissions
//   (FILE-013-S1); notDetermined and granted give none.
// * The catalog's usage texts equal the built app's Info.plist, and no Photos library key exists.
// Pure value checks; each test well under a second (owner rule 7).
import AVFoundation
import AudioCore
import CameraLayer
import CaptureKit
import CaptureUI
import PerformanceControl
import XCTest
@testable import projectM_iOS

final class PermissionCatalogTests: XCTestCase {
    private typealias C = PermissionCatalog

    private static let micDenied = "Microphone permission denied. Enable it in Settings › Privacy › Microphone."
    private static let cameraDenied = "Camera access is off. To show the camera, allow it in Settings."
    private static let cameraRestricted = "Camera access is restricted on this device. It can be allowed in Settings if your restrictions permit."
    private static let networkDenied = "Local network access is off for projectM in Settings › Privacy & Security › Local Network."
    private static let screenDenied = "Screen recording not allowed"

    // MARK: Entries

    func testOneEntryPerPermissionWithItsKey() {
        XCTAssertEqual(C.entries.map(\.permission), AppPermission.allCases)
        XCTAssertEqual(C.entries.map(\.infoPlistKey), ["NSMicrophoneUsageDescription", "NSCameraUsageDescription",
                                                      "NSLocalNetworkUsageDescription", "NSScreenCaptureUsageDescription"])
        XCTAssertEqual(C.entries.map(\.name), ["Microphone", "Camera", "Local Network", "Screen recording (System/App Capture)"])
        for entry in C.entries {
            XCTAssertFalse(entry.features.isEmpty, entry.name)
            XCTAssertFalse(entry.askedWhen.isEmpty, entry.name)
        }
    }

    /// The usage texts are the built Info.plist's, and the microphone's is the FR-005 explainer (FR-019).
    func testUsageTextsMatchTheBuiltInfoPlist() {
        let info = Bundle.main.infoDictionary ?? [:]
        for entry in C.entries {
            XCTAssertEqual(info[entry.infoPlistKey] as? String, entry.usageDescription, entry.infoPlistKey)
        }
        XCTAssertEqual(C.entry(.microphone).usageDescription, UIStrings.microphoneExplainer)
    }

    /// Every usage key in the built Info.plist is in the catalog, and none is a Photos library key.
    func testNoUndeclaredUsageKeyAndNoPhotosLibraryKey() {
        let info = Bundle.main.infoDictionary ?? [:]
        let usageKeys = Set(info.keys.filter { (key: String) -> Bool in key.hasSuffix("UsageDescription") })
        XCTAssertEqual(usageKeys, Set(C.entries.map(\.infoPlistKey)))
        XCTAssertNil(info["NSPhotoLibraryUsageDescription"])
        XCTAssertNil(info["NSPhotoLibraryAddUsageDescription"])
        XCTAssertFalse(C.photosLibrary.isEmpty)
    }

    // MARK: Notices (denied and restricted for every permission)

    func testDeniedAndRestrictedNotices() {
        let expected: [(AppPermission, PermissionState, String, Bool)] = [
            (.microphone, .denied, Self.micDenied, true),
            (.microphone, .restricted, Self.micDenied, true),      // iOS reports a restriction as denied
            (.camera, .denied, Self.cameraDenied, true),
            (.camera, .restricted, Self.cameraRestricted, true),
            (.localNetwork, .denied, Self.networkDenied, true),
            (.localNetwork, .restricted, Self.networkDenied, true), // no restricted state in iOS
            (.screenCapture, .denied, Self.screenDenied, false),    // no per-app switch in Settings
            (.screenCapture, .restricted, Self.screenDenied, false),
        ]
        for (permission, state, text, settings) in expected {
            let notice = C.notice(permission, state)
            // UIX-015-R7, R8: camera and Local Network name their fallback; only the camera offers Dismiss.
            let fallback: String? = permission == .camera ? C.cameraFallback : permission == .localNetwork ? C.localNetworkFallback : nil
            XCTAssertEqual(notice, PermissionNotice(permission: permission, state: state, text: text, offersSettings: settings,
                                                    fallback: fallback, offersDismiss: permission == .camera),
                           "\(permission) \(state)")
        }
    }

    func testNoNoticeWhenNotDeterminedOrGranted() {
        for permission in AppPermission.allCases {
            XCTAssertNil(C.notice(permission, .notDetermined), "\(permission)")
            XCTAssertNil(C.notice(permission, .granted), "\(permission)")
        }
    }

    /// The catalog references the texts fixed by other contracts; it never drifts from them.
    @MainActor
    func testTextsAreTheFeatureTexts() {
        XCTAssertEqual(C.notice(.microphone, .denied)?.text, UIStrings.message(.permissionDenied))
        XCTAssertEqual(C.notice(.screenCapture, .denied)?.text, UIStrings.message(.screenRecordingNotAllowed))
        XCTAssertEqual(C.notice(.camera, .denied)?.text, CameraFeedState.denied.notice)
        XCTAssertEqual(C.notice(.camera, .restricted)?.text, CameraFeedState.restricted.notice)
        XCTAssertEqual(OSCReceiverCoordinator.statusText(for: .failed(port: 9000, .localNetworkDenied), enabled: true),
                       C.notice(.localNetwork, .denied)?.text)
        // The microphone banner offers Open Settings, the screen-capture banner does not (FR-015).
        XCTAssertTrue(BannerAction.actions(for: .permissionDenied).contains(.openSettings))
        XCTAssertFalse(BannerAction.actions(for: .screenRecordingNotAllowed).contains(.openSettings))
    }

    // MARK: Mappings

    func testMicrophoneMapping() {
        XCTAssertEqual(C.state(microphone: .undetermined), .notDetermined)
        XCTAssertEqual(C.state(microphone: .granted), .granted)
        XCTAssertEqual(C.state(microphone: .denied), .denied)
    }

    func testCameraAuthorizationMapping() {
        XCTAssertEqual(C.state(cameraAuthorization: .notDetermined), .notDetermined)
        XCTAssertEqual(C.state(cameraAuthorization: .authorized), .granted)
        XCTAssertEqual(C.state(cameraAuthorization: .denied), .denied)
        XCTAssertEqual(C.state(cameraAuthorization: .restricted), .restricted)
    }

    func testCameraFeedMappingAndNotice() {
        XCTAssertEqual(C.state(camera: .requestingAccess), .notDetermined)
        XCTAssertEqual(C.state(camera: .running), .granted)
        XCTAssertEqual(C.state(camera: .denied), .denied)
        XCTAssertEqual(C.state(camera: .restricted), .restricted)
        XCTAssertNil(C.state(camera: .unavailable))
        XCTAssertEqual(C.cameraNotice(for: .restricted)?.text, Self.cameraRestricted)
        XCTAssertEqual(C.cameraNotice(for: .restricted)?.offersSettings, true)
        // Not a permission state: CAM-001's notice, no Open Settings.
        let none = C.cameraNotice(for: .unavailable)
        XCTAssertEqual(none?.text, CameraFeedState.unavailable.notice)
        XCTAssertNil(none?.state)
        XCTAssertEqual(none?.offersSettings, false)
        XCTAssertNil(C.cameraNotice(for: .running))
    }

    func testLocalNetworkMapping() {
        XCTAssertEqual(C.state(localNetwork: .listening(port: 9000)), .granted)
        XCTAssertEqual(C.state(localNetwork: .failed(port: 9000, .localNetworkDenied)), .denied)
        XCTAssertNil(C.state(localNetwork: .failed(port: 9000, .portInUse)))
        XCTAssertNil(C.state(localNetwork: .off), "iOS has no Local Network query")
    }

    func testScreenCaptureMapping() {
        XCTAssertEqual(C.state(screenCaptureAvailability: .unavailable(.screenRecordingNotAllowed), stopReason: nil), .restricted)
        XCTAssertEqual(C.state(screenCaptureAvailability: .available, stopReason: .screenRecordingNotAllowed), .denied)
        XCTAssertNil(C.state(screenCaptureAvailability: .unavailable(.unsupportedOS), stopReason: nil))
        XCTAssertNil(C.state(screenCaptureAvailability: .available, stopReason: nil))
    }
}
