// SharedNoiseSourceTests.swift — VIS-013-T03 (VIS-013-R2): the Noise Flow material and VIS-013's Noise Field use one
// definition of SHD-006's seeded noise. The material's shader literal (which SHD-001's source-safety rule keeps free
// of interpolation) must contain VisualGenerators' `SeededNoiseShader.functions` verbatim, and the material's CPU
// reference must give the shared mirror's values. MaterialNoiseTests' recorded digests prove the pictures unchanged.
@testable import ProceduralMaterials
import VisualGenerators
import XCTest

#if canImport(Metal) && !COMPOSITOR_NO_METAL

final class SharedNoiseSourceTests: XCTestCase {
    func testTheMaterialShaderContainsTheSharedNoiseFunctionsVerbatim() {
        XCTAssertTrue(ProceduralMaterialShaders.source.contains(SeededNoiseShader.functions),
                      "mat_nhash, mat_snoise and mat_sfbm must match VisualGenerators' SeededNoiseShader.functions")
    }
}
#endif

final class SharedNoiseReferenceTests: XCTestCase {
    func testTheMaterialReferenceIsTheSharedMirror() {
        let s = NoiseTextureSettings(seed: 4242, octaves: 5, lacunarity: 2.5, gain: 0.6, warpAmount: 1.5, warpFrequency: 1.5)
        let q = SIMD2<Float>(1.7, -3.2)
        XCTAssertEqual(NoiseTextureReference.fbm(q, settings: s, octaves: 5, field: 2),
                       SeededNoise.fbm(q, octaves: 5, lacunarity: 2.5, gain: 0.6, seed: 4242, field: 2))
        XCTAssertEqual(NoiseTextureReference.value(at: q, settings: s),
                       SeededNoise.warped(q, octaves: 5, lacunarity: 2.5, gain: 0.6, seed: 4242, warpAmount: 1.5, warpFrequency: 1.5))
    }
}
