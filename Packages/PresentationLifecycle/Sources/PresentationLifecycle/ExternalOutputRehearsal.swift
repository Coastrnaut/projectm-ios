// ExternalOutputRehearsal.swift — OUT-012: preview on the device what an external display of a chosen
// profile would show (spec specs/184-out-012-display-rehearsal; research OUT-012-D1, D2; contract
// contracts/rehearsal.md C1).
//
// The placement is OUT-004's `ExternalOutputPlacement`, built with the same initializer the real
// external slot uses; the profile's pixel aspect ratio stands in for the screen mode's. The preview
// transform then maps the slot (W × H points, pixels of aspect p) into a device area A × B so the frame
// has the display's physical shape:
//
//     s = min(A / (W·p), B / H)     scaleX = s·p     scaleY = s     frame centred in A × B
//
// so a circle that is round on the glass is round in the preview. Pure Swift with no UIKit (tested on
// the host and Linux).

/// A display to rehearse for: its size in points (the slot) and its own pixel aspect ratio (what its
/// screen mode would report). Transient: never stored (OUT-012-R6).
public struct RehearsalProfile: Sendable, Equatable {
    public static let minimumSide: Double = 160
    public static let maximumSide: Double = 7680

    public let width: Double
    public let height: Double
    /// The display's own pixel aspect ratio, sanitised to 0.5…2 (else 1).
    public let pixelAspect: Double
    /// Shown in the picker, for example "16:9 · 1920 × 1080".
    public let name: String
    /// Spoken, for example "16 by 9".
    public let spokenName: String

    public init(width: Double, height: Double, pixelAspect: Double, name: String, spokenName: String) {
        self.width = Self.clampedSide(width)
        self.height = Self.clampedSide(height)
        self.pixelAspect = ExternalPixelAspect.sanitized(pixelAspect)
        self.name = name
        self.spokenName = spokenName
    }

    /// A custom size, clamped to 160…7680 points per side; named "W × H", spoken "W by H".
    public static func custom(width: Double, height: Double, pixelAspect: Double) -> RehearsalProfile {
        let w: Int = Int(clampedSide(width).rounded())
        let h: Int = Int(clampedSide(height).rounded())
        return RehearsalProfile(width: Double(w), height: Double(h), pixelAspect: pixelAspect,
                                name: "\(w) × \(h)", spokenName: "\(w) by \(h)")
    }

    /// Finite values clamped to 160…7680; anything else reads 1920 (a usable default).
    public static func clampedSide(_ value: Double) -> Double {
        guard value.isFinite else { return 1920 }
        return min(max(value, minimumSide), maximumSide)
    }
}

/// The preset sizes offered by the rehearsal (OUT-012-R2). Raw values are stable identifiers.
public enum RehearsalSize: String, Sendable, Equatable, CaseIterable {
    case hd1080, standard4x3, ultrawide, custom

    /// The preset's profile with the display's own PAR; Custom uses the given size.
    public func profile(pixelAspect: Double, customWidth: Double = 1280, customHeight: Double = 1024) -> RehearsalProfile {
        switch self {
        case .hd1080:
            RehearsalProfile(width: 1920, height: 1080, pixelAspect: pixelAspect, name: "16:9 · 1920 × 1080", spokenName: "16 by 9")
        case .standard4x3:
            RehearsalProfile(width: 1024, height: 768, pixelAspect: pixelAspect, name: "4:3 · 1024 × 768", spokenName: "4 by 3")
        case .ultrawide:
            RehearsalProfile(width: 2560, height: 1080, pixelAspect: pixelAspect, name: "21:9 · 2560 × 1080", spokenName: "21 by 9")
        case .custom:
            RehearsalProfile.custom(width: customWidth, height: customHeight, pixelAspect: pixelAspect)
        }
    }

    public var title: String {
        switch self {
        case .hd1080: "16:9 · 1920 × 1080"
        case .standard4x3: "4:3 · 1024 × 768"
        case .ultrawide: "21:9 · 2560 × 1080"
        case .custom: "Custom"
        }
    }
}

/// Maps slot points into the preview area (contract C1).
public struct RehearsalPreviewTransform: Sendable, Equatable {
    public let scaleX: Double
    public let scaleY: Double
    public let originX: Double
    public let originY: Double
    public let frameWidth: Double
    public let frameHeight: Double

    /// A slot point → a preview point.
    public func map(x: Double, y: Double) -> (x: Double, y: Double) {
        (originX + x * scaleX, originY + y * scaleY)
    }
}

/// A rehearsal: a profile, the user's OUT-004 correction and the device's shape.
public struct ExternalOutputRehearsal: Sendable, Equatable {
    public let profile: RehearsalProfile
    public let correction: ExternalOutputCorrection
    public let deviceAspect: Double?
    /// Exactly what a real external slot of this profile computes (OUT-012-R3).
    public let placement: ExternalOutputPlacement

    public init(profile: RehearsalProfile, correction: ExternalOutputCorrection, deviceAspect: Double?) {
        self.profile = profile
        self.correction = correction
        self.deviceAspect = deviceAspect
        placement = ExternalOutputPlacement(slotWidth: profile.width, slotHeight: profile.height, correction: correction,
                                            screenPixelAspect: profile.pixelAspect, deviceAspect: deviceAspect)
    }

    /// The PAR the real slot would use (the setting's override, else the profile's own).
    public var appliedPixelAspect: Double { correction.pixelAspect.resolved(screen: profile.pixelAspect) }

    /// Where a point of the visual's bounds (u, v in 0…1) lands in the slot.
    public func slotPoint(u: Double, v: Double) -> (x: Double, y: Double) {
        let p: ExternalOutputPlacement = placement
        let x: Double = p.centerX + (u - 0.5) * p.boundsWidth * p.scaleX
        let y: Double = p.centerY + (v - 0.5) * p.boundsHeight
        return (x, y)
    }

    /// The slot scaled into a `width` × `height` area in the display's physical shape, centred.
    /// Stretch shows the pixels as the display shows them too: the frame is always physical.
    public func preview(width: Double, height: Double) -> RehearsalPreviewTransform {
        let par: Double = appliedPixelAspect
        let physicalWidth: Double = profile.width * par
        let usable: Bool = width.isFinite && height.isFinite && width > 0 && height > 0
        let scale: Double = usable ? min(width / physicalWidth, height / profile.height) : 0
        let frameWidth: Double = physicalWidth * scale
        let frameHeight: Double = profile.height * scale
        let originX: Double = usable ? (width - frameWidth) / 2 : 0
        let originY: Double = usable ? (height - frameHeight) / 2 : 0
        return RehearsalPreviewTransform(scaleX: scale * par, scaleY: scale, originX: originX, originY: originY,
                                         frameWidth: frameWidth, frameHeight: frameHeight)
    }

    /// "pillarbox", "letterbox", "cropped", "stretched" or "no bars".
    public var barsWord: String {
        if correction.fit == .stretch { return "stretched" }
        switch placement.bars {
        case .pillarbox: return "pillarbox"
        case .letterbox: return "letterbox"
        case .none: break
        }
        let p: ExternalOutputPlacement = placement
        let overflows: Bool = p.frameWidth > p.slotWidth + 0.5 || p.frameHeight > p.slotHeight + 0.5
        return overflows ? "cropped" : "no bars"
    }

    /// The preview's VoiceOver label (OUT-012-R7), e.g. "Previewing 16 by 9 display, fit, pillarbox".
    public var spokenDescription: String {
        let head: String = "Previewing " + profile.spokenName + " display, " + correction.fit.rawValue + ", " + barsWord
        let par: Double = appliedPixelAspect
        guard abs(par - 1) > 0.001 else { return head }
        let parText: String = String(Double((par * 10).rounded()) / 10)
        return head + ", pixel aspect " + parText
    }

    /// "profile=WxH par=x.xx fit=… shape=… frame=WxH bars=…" (DEBUG probe, tests).
    public var probe: String {
        let w: Int = Int(profile.width.rounded()), h: Int = Int(profile.height.rounded())
        let fw: Int = Int(placement.frameWidth.rounded()), fh: Int = Int(placement.frameHeight.rounded())
        let parText: String = Self.twoDecimals(appliedPixelAspect)
        let head: String = "profile=\(w)x\(h) par=" + parText + " fit=" + correction.fit.rawValue
        let tail: String = " shape=" + correction.shape.rawValue + " frame=\(fw)x\(fh) bars=" + placement.bars.rawValue
        return head + tail
    }

    /// Two decimals without Foundation's `String(format:)` (Linux-safe, locale-free).
    static func twoDecimals(_ value: Double) -> String {
        let hundredths: Int = Int((value * 100).rounded())
        let whole: Int = hundredths / 100
        let fraction: Int = abs(hundredths % 100)
        let pad: String = fraction < 10 ? "0" : ""
        return "\(whole)." + pad + "\(fraction)"
    }
}
