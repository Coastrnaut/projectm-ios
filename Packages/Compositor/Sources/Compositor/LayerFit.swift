// LayerFit.swift — how a layer's content (a photo, a video) is fitted to the output: fill, fit,
// stretch or pixel-accurate, around an anchor (CMP-006-R1 to R6; research CMP-006-D1 to D4;
// specs/101-cmp-006-aspect-fitting/contracts/aspect-fitting.md).
//
// CPU only (builds on Linux). The placement is the part of the content the output shows, in content
// fractions: output point p (0…1, top-left) shows content coordinate `offset + p·visible`; outside
// 0…1 the layer is transparent. With content Wc × Hc and output Wo × Ho pixels:
//
//     fill           s = max(Wo/Wc, Ho/Hc)          visible = (Wo/(Wc·s), Ho/(Hc·s)) ≤ 1
//     fit            s = min(Wo/Wc, Ho/Hc)          visible ≥ 1 (transparent bars)
//     stretch        visible = (1, 1), offset = 0 (anchor ignored)
//     pixelAccurate  s = k output pixels per content pixel (default 1; not the device's scale)
//
// offset = anchor·(1 − visible), so the anchor's content point lands on the same fraction of the
// output at every output size (the crop chosen in portrait is kept in landscape). pixelAccurate
// rounds the content's origin to a whole output pixel, so every output pixel centre falls on a texel
// centre and nothing is resampled. Fitting happens inside the layer picture; the CMP-005 transform,
// CMP-003 opacity and CMP-004 blend mode apply to the fitted picture afterwards.
//
// Every intermediate is a named, typed value: long mixed expressions time out the type checker on
// Linux and Xcode 26 (research CMP-006-D4).

/// The four ways content is fitted to the output. Raw values are the saved names (SCN-001).
public enum LayerFitMode: String, Sendable, Equatable, CaseIterable {
    /// Cover the output keeping the content's shape; the overflow is cropped around the anchor.
    case fill
    /// Show all of the content keeping its shape; transparent bars on the other axis.
    case fit
    /// Cover the output exactly, ignoring the content's shape.
    case stretch
    /// One content pixel per output pixel, placed by the anchor; cropped or transparent around it.
    case pixelAccurate
}

/// A fit mode and its anchor (content fractions; (0.5, 0.5) is the centre).
public struct LayerFit: Sendable, Equatable {
    public let mode: LayerFitMode
    /// Each component 0…1 (clamped; non-finite reads 0.5).
    public let anchor: LayerPoint

    public init(mode: LayerFitMode, anchor: LayerPoint = LayerPoint(x: 0.5, y: 0.5)) {
        self.mode = mode
        func one(_ v: Double) -> Double {
            guard v.isFinite else { return 0.5 }
            let c: Double = min(max(v, 0), 1)
            return c == 0 ? 0 : c   // −0 is stored as 0
        }
        self.anchor = LayerPoint(x: one(anchor.x), y: one(anchor.y))
    }

    /// What photo and video draw when no fit is set: fill at the centre (today's drawing).
    public static let `default` = LayerFit(mode: .fill)
}

/// Where the content lands in the output for one content size, output size and fit.
public struct LayerFitPlacement: Sendable, Equatable {
    /// Width and height of the output, in units of the content's width and height.
    public let visibleWidth: Double
    public let visibleHeight: Double
    /// Content coordinate of the output's top-left corner.
    public let offsetX: Double
    public let offsetY: Double
    /// The sizes it was computed for (pixels).
    public let contentWidth: Int
    public let contentHeight: Int
    public let outputWidth: Int
    public let outputHeight: Int

    /// Any size ≤ 0 gives the identity (the whole content stretched over the output).
    /// `pixelsPerContentPixel` is used by pixelAccurate only (non-finite or ≤ 0 reads 1).
    public init(contentWidth: Int, contentHeight: Int, outputWidth: Int, outputHeight: Int, fit: LayerFit,
                pixelsPerContentPixel: Double = 1) {
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        guard contentWidth > 0, contentHeight > 0, outputWidth > 0, outputHeight > 0 else {
            visibleWidth = 1; visibleHeight = 1; offsetX = 0; offsetY = 0
            return
        }
        let wc: Double = Double(contentWidth)
        let hc: Double = Double(contentHeight)
        let wo: Double = Double(outputWidth)
        let ho: Double = Double(outputHeight)
        let ax: Double = fit.anchor.x
        let ay: Double = fit.anchor.y
        switch fit.mode {
        case .fill, .fit:
            let sx: Double = wo / wc
            let sy: Double = ho / hc
            // The binding axis is exactly 1, the other the ratio of the two scales.
            let xBinds: Bool = fit.mode == .fill ? sx >= sy : sx <= sy
            let vw: Double = xBinds ? 1 : sx / sy
            let vh: Double = xBinds ? sy / sx : 1
            let ox: Double = ax * (1 - vw)
            let oy: Double = ay * (1 - vh)
            visibleWidth = vw; visibleHeight = vh; offsetX = ox; offsetY = oy
        case .stretch:
            visibleWidth = 1; visibleHeight = 1; offsetX = 0; offsetY = 0
        case .pixelAccurate:
            let k: Double = pixelsPerContentPixel.isFinite && pixelsPerContentPixel > 0 ? pixelsPerContentPixel : 1
            let shownW: Double = wc * k
            let shownH: Double = hc * k
            let spareW: Double = wo - shownW
            let spareH: Double = ho - shownH
            let originX: Double = (ax * spareW).rounded()   // whole output pixels
            let originY: Double = (ay * spareH).rounded()
            let ox: Double = -originX / shownW
            let oy: Double = -originY / shownH
            visibleWidth = wo / shownW; visibleHeight = ho / shownH
            offsetX = ox == 0 ? 0 : ox; offsetY = oy == 0 ? 0 : oy
        }
    }

    /// The content coordinate shown at output point (`x`, `y`) (both 0…1, top-left); outside 0…1
    /// means "no content here". The shaders do the same arithmetic.
    public func textureCoordinate(x: Double, y: Double) -> LayerPoint {
        let tx: Double = offsetX + x * visibleWidth
        let ty: Double = offsetY + y * visibleHeight
        return LayerPoint(x: tx, y: ty)
    }

    /// The content's rectangle in output fractions: origin and size.
    public var contentRect: (x: Double, y: Double, width: Double, height: Double) {
        let w: Double = 1 / visibleWidth
        let h: Double = 1 / visibleHeight
        let x: Double = -offsetX * w
        let y: Double = -offsetY * h
        return (x, y, w, h)
    }

    /// Output pixels per content pixel, horizontally and vertically.
    public var pixelScale: (x: Double, y: Double) {
        guard contentWidth > 0, contentHeight > 0, outputWidth > 0, outputHeight > 0 else { return (1, 1) }
        let shownW: Double = Double(outputWidth) / visibleWidth
        let shownH: Double = Double(outputHeight) / visibleHeight
        return (shownW / Double(contentWidth), shownH / Double(contentHeight))
    }

    /// Horizontal ÷ vertical pixel scale: 1 means square content pixels (every mode but stretch).
    public var pixelAspect: Double {
        let s = pixelScale
        return s.x / s.y
    }

    /// Normalized content (0…1, top-left) → normalized output.
    public var contentToOutput: LayerTransformMatrix {
        let m00: Double = 1 / visibleWidth
        let m11: Double = 1 / visibleHeight
        let m02: Double = -offsetX * m00
        let m12: Double = -offsetY * m11
        return LayerTransformMatrix(m00: m00, m01: 0, m02: m02, m10: 0, m11: m11, m12: m12)
    }

    /// Normalized content → normalized output after the layer's CMP-005 transform (fit first, then
    /// the transform, as the compositor draws it).
    public func placed(by transform: LayerTransform) -> LayerTransformMatrix {
        let t: LayerTransformMatrix = transform.matrix(outputWidth: outputWidth, outputHeight: outputHeight)
        return t * contentToOutput
    }
}
