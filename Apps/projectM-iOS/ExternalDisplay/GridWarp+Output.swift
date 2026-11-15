// GridWarp+Output.swift — OUT-008 (spec specs/309-out-008-grid-warp, contract C4): a validated `GridWarp` as the render
// description the final passes draw. The identity without guides is `.none`: no pass runs (OUT-008-R7).
import Compositor
import PresentationLifecycle

extension GridWarp {
    func outputMesh(showsGuides: Bool) -> OutputWarpMesh {
        guard isValid else { return .none }
        if isIdentity, !showsGuides { return .none }
        let points: [SIMD2<Float>] = points.map { (p: GridWarpPoint) -> SIMD2<Float> in SIMD2<Float>(Float(p.x), Float(p.y)) }
        return OutputWarpMesh(columns: columns, rows: rows, points: points, showsGuides: showsGuides)
    }
}
