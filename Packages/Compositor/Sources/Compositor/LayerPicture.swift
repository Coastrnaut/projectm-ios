// LayerPicture.swift — what a layer's picture is (CMP-001-R1, R2, R6; research CMP-001-D2;
// contracts/layer-source.md "Pictures").
//
// Every picture exchanged between a layer and the compositor: 16-bit float RGBA, linear light with
// sRGB (Rec. 709) primaries and D65 white, premultiplied alpha, row 0 at the top, the output's full
// size. The fixed members exist so later rows (MED, CAM) can add a declared format or space without
// changing the contract's shape.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

public enum LayerPixelFormat: Sendable, Equatable {
    /// Four 16-bit floats per pixel (RGBA).
    case rgba16Float
}

public enum LayerColorSpace: Sendable, Equatable {
    /// Linear light, sRGB/Rec. 709 primaries, D65 white.
    case linearSRGB
}

public enum LayerAlphaConvention: Sendable, Equatable {
    /// Color channels are already multiplied by alpha; "over" is src + dst × (1 − src.a).
    case premultiplied
}

public enum LayerPictureOrigin: Sendable, Equatable {
    /// Row 0 is the top of the picture (Metal's texture convention).
    case topLeft
}

public struct LayerPictureDescriptor: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let format: LayerPixelFormat
    public let colorSpace: LayerColorSpace
    public let alpha: LayerAlphaConvention
    public let origin: LayerPictureOrigin

    /// Nil unless both sides are at least 1 pixel.
    public init?(width: Int, height: Int) {
        guard width >= 1, height >= 1 else { return nil }
        self.width = width
        self.height = height
        format = .rgba16Float
        colorSpace = .linearSRGB
        alpha = .premultiplied
        origin = .topLeft
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
extension LayerPictureDescriptor {
    /// The pixel format of every layer picture.
    public static let metalPixelFormat: MTLPixelFormat = .rgba16Float

    /// `.private`, render target + shader read + shader write, one mip level.
    public func textureDescriptor() -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.metalPixelFormat, width: width, height: height,
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .private
        return d
    }
}
#endif
