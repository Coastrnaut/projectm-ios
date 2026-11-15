// PixelSortPass.swift — FX-011 "Pixel sorting approximation" on the GPU (specs/310-fx-011-pixel-sorting,
// contracts/pixel-sort.md C1-C3, research FX-011-D1 to D4; ADR-0121).
//
// One compute dispatch `cmp_pixel_sort` per active frame: one threadgroup of `span` threads per tile of a row (or a
// column). Each thread loads its pixel into threadgroup memory, then runs two loops of exactly `span` steps — the bounds
// of its segment (the maximal qualifying run around it inside the tile), then its stable rank among that segment's
// pixels — and writes its pixel to segment start + rank; a pixel that does not qualify writes itself in place, and a
// thread beyond the frame's edge (a partial last tile) writes nothing. The ranks of a segment are a permutation of its
// places, so every output pixel is written exactly once and the output is the input rearranged (no value computed). The
// work does not depend on the picture. The output is one pooled picture (composite size, `rgba16Float`; the pool's
// pictures allow shader writes), which the next effect, the flash guard and every output read. The source is a module
// constant spliced after `LensDistortionPass.source` at the compositor's existing reviewed compile site (SHD-011,
// ADR-0024) and listed in `CompositorShaderSources.archived`. The picture is taken from the pool on the first active
// frame at a size and returned (fenced by the last command buffer) when the effect turns inactive, at a size change and
// with the compositor. Per frame only Metal's own command objects are created; the 16-byte block is copied by
// `setBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class PixelSortPass {
    /// `cmp_pixel_sort` (the same result as `PixelSort.referenceAlways`).
    static let source = """

    struct CMPPixelSort { float threshold; uint span; uint vertical; uint pad; };

    // FX-011: the luminance in `PixelSort.luminance`'s order of operations; qualifies = finite and >= threshold.
    static inline float cmp_pixel_sort_luma(float4 c) {
        float r = c.r * 0.2126;
        float g = c.g * 0.7152;
        float b = c.b * 0.0722;
        return (r + g) + b;
    }

    kernel void cmp_pixel_sort(texture2d<float, access::read> source [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               constant CMPPixelSort &c [[buffer(0)]],
                               uint3 group [[threadgroup_position_in_grid]],
                               uint index [[thread_index_in_threadgroup]]) {
        threadgroup float4 pixels[64];
        threadgroup float lumas[64];
        threadgroup bool marks[64];
        uint span = min(c.span, 64u);
        uint width = source.get_width();
        uint height = source.get_height();
        uint2 origin = c.vertical != 0 ? uint2(group.x, group.y * span) : uint2(group.x * span, group.y);
        uint2 step = c.vertical != 0 ? uint2(0, 1) : uint2(1, 0);
        uint2 position = origin + step * index;
        bool inside = index < span && position.x < width && position.y < height;
        float4 own = inside ? source.read(position) : float4(0.0);
        float luma = cmp_pixel_sort_luma(own);
        bool mark = inside && !isnan(luma) && !isinf(luma) && luma >= c.threshold;
        if (index < 64u) {
            pixels[index] = own;
            lumas[index] = luma;
            marks[index] = mark;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (!inside) { return; }
        if (!mark) {
            output.write(own, position);
            return;
        }
        // Segment bounds: one fixed loop over the tile.
        uint start = 0;
        uint end = span;
        for (uint j = 0; j < span; ++j) {
            bool off = !marks[j];
            if (off && j < index) { start = j + 1; }
            if (off && j > index && j < end) { end = j; }
        }
        // Stable rank inside [start, end): one fixed loop over the tile.
        uint rank = 0;
        for (uint j = 0; j < span; ++j) {
            float other = lumas[j];
            bool inSegment = j >= start && j < end;
            bool before = other < luma || (other == luma && j < index);
            rank += (inSegment && before) ? 1u : 0u;
        }
        output.write(pixels[index], origin + step * (start + rank));
    }
    """

    private let pipeline: MTLComputePipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and dispatches encoded (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var dispatches = 0

    init(device: MTLDevice, library: MTLLibrary) throws(CompositorError) {
        let function = try CompositorShaders.function(library, "cmp_pixel_sort")
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw .pipelineUnavailable("FX-011 pixel sort: \(error.localizedDescription)")
        }
        guard pipeline.maxTotalThreadsPerThreadgroup >= PixelSort.maxSpan else {
            throw .pipelineUnavailable("FX-011 pixel sort: \(pipeline.maxTotalThreadsPerThreadgroup) threads per group")
        }
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the sort of `input` with `block` (its span the plan's effective span); returns the sorted picture (owned
    /// by this pass, valid in `commandBuffer` until the next frame), nil when the picture or the encoder cannot be made.
    func encode(input: MTLTexture, block: PixelSort.Block, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-011 pixel sort"
            picture = made
            allocations += 1
        }
        guard let output = picture, let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        let span = Int(block.span)
        let vertical: Bool = block.vertical != 0
        let groups: MTLSize = vertical
            ? MTLSize(width: input.width, height: (input.height + span - 1) / span, depth: 1)
            : MTLSize(width: (input.width + span - 1) / span, height: input.height, depth: 1)
        let threads: MTLSize = vertical ? MTLSize(width: 1, height: span, depth: 1) : MTLSize(width: span, height: 1, depth: 1)
        encoder.label = "FX-011 pixel sort"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        var bytes: PixelSort.Block = block
        encoder.setBytes(&bytes, length: MemoryLayout<PixelSort.Block>.stride, index: 0)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()
        dispatches += 1
        return output
    }
}
#endif
