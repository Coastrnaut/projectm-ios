// CameraLens.swift — the back camera's lenses (CAM-003-R1, R2, R5; data-model.md).
//
// Only three physical lens kinds are ever offered: ultra wide, wide and telephoto, in that display
// order (widest first). An inventory lists the ones a device has; `FixedCameraLensInventory` is the
// stand-in for tests, the simulator and DEBUG UI tests, `AVCameraLensInventory` (iOS) asks the system.
// Listing opens no camera and asks for nothing (CAM-003-R3).

import Foundation

/// A back camera lens (CAM-003-R1). Stored by the app as the raw value.
public enum CameraLens: String, Sendable, Equatable, CaseIterable {
    case ultraWide
    case wide
    case telephoto

    /// "Ultra Wide", "Wide" or "Telephoto" (the Settings row, CAM-003-R11).
    public var title: String {
        switch self {
        case .ultraWide: "Ultra Wide"
        case .wide: "Wide"
        case .telephoto: "Telephoto"
        }
    }

    /// A stored raw value; anything unknown or missing is the wide lens (CAM-003-R5).
    public init(stored: String?) {
        self = stored.flatMap(CameraLens.init(rawValue:)) ?? .wide
    }

    /// The lenses in display order (ultra wide, wide, telephoto), each once.
    public static func ordered<S: Sequence>(_ lenses: S) -> [CameraLens] where S.Element == CameraLens {
        let present: Set<CameraLens> = Set(lenses)
        return allCases.filter { (lens: CameraLens) -> Bool in present.contains(lens) }
    }
}

/// The back lenses this device has (CAM-003-R1). Reading it never starts a camera (R3).
public protocol CameraLensInventory: AnyObject {
    /// Distinct, in display order. Empty when the device has no back camera.
    var backLenses: [CameraLens] { get }
}

extension CameraLensInventory {
    /// CAM-003-R5: the stored lens when this device has it, else the wide lens.
    public func resolve(_ stored: CameraLens) -> CameraLens {
        backLenses.contains(stored) ? stored : .wide
    }

    /// CAM-003-R2: the lenses the Settings row offers for a position: none for the front camera or a
    /// device with fewer than two back lenses (the row is then hidden), else every listed lens.
    public func offeredLenses(for position: CameraPosition) -> [CameraLens] {
        let lenses: [CameraLens] = backLenses
        return position == .back && lenses.count >= 2 ? lenses : []
    }
}

/// A fixed inventory (tests, the simulator and DEBUG UI tests; CAM-003-R10).
public final class FixedCameraLensInventory: CameraLensInventory {
    public let backLenses: [CameraLens]

    public init<S: Sequence>(_ lenses: S) where S.Element == CameraLens {
        backLenses = CameraLens.ordered(lenses)
    }

    /// A comma-separated list of raw values ("wide,ultraWide"); unknown names are ignored.
    public convenience init(list: String) {
        let names: [Substring] = list.split(separator: ",")
        let lenses: [CameraLens] = names.compactMap { (name: Substring) -> CameraLens? in
            CameraLens(rawValue: name.trimmingCharacters(in: .whitespaces))
        }
        self.init(lenses)
    }
}
