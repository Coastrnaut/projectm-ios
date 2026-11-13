// LayerSlots.swift — which of a layer's pictures to render into and which to show (CMP-001-R6 to
// R8; research CMP-001-D6; data-model.md "LayerSlots transitions"). CPU only, so the fallback rule
// is tested on every host.
//
// A `.lastGoodFrame` layer has two pictures and always renders into the one not holding its last
// success, so a failed or half-drawn frame never overwrites the good one. A `.transparent` layer
// has one.

public struct LayerSlots: Sendable, Equatable {
    public let fallback: LayerFallback
    /// 1 or 2.
    public let pictureCount: Int
    /// The picture the next frame renders into.
    public private(set) var renderIndex = 0
    /// The picture holding the last successful frame, if any.
    public private(set) var lastGoodIndex: Int?
    /// False after a failed `prepare`.
    public private(set) var isAvailable = false

    public init(fallback: LayerFallback) {
        self.fallback = fallback
        pictureCount = fallback == .lastGoodFrame ? 2 : 1
    }

    /// After `prepare` (a first frame, a new size, or a retry): pictures are new, nothing is good yet.
    public mutating func prepared(ok: Bool) {
        isAvailable = ok
        renderIndex = 0
        lastGoodIndex = nil
    }

    /// The frame rendered into `renderIndex` succeeded: returns the picture to show.
    public mutating func frameSucceeded() -> Int {
        let shown = renderIndex
        lastGoodIndex = shown
        if pictureCount == 2 { renderIndex = 1 - shown }
        return shown
    }

    /// The frame failed: returns the picture to show (the last good one), or nil for nothing.
    public mutating func frameFailed() -> Int? {
        fallback == .lastGoodFrame ? lastGoodIndex : nil
    }
}
