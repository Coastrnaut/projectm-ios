// AcceleratedRealFFT.swift — the vDSP real FFT (research ANL-001-D3). Compiled only where
// Accelerate exists and `ANALYSIS_NO_ACCELERATE` is not defined.
//
// One `vDSP_create_fftsetup` for log2 N = 13 serves every smaller size. vDSP's forward real FFT
// (`vDSP_fft_zrip`) returns 2·X[k] with DC packed in realp[0] and Nyquist in imagp[0]; this type
// returns the true |X[k]|. After init nothing allocates.
#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
import Accelerate

final class AcceleratedRealFFT {
    private let setup: FFTSetup
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let half = FFTSize.maximum.rawValue / 2

    init() {
        guard let setup = vDSP_create_fftsetup(vDSP_Length(FFTSize.maximum.log2), FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed for log2 N = \(FFTSize.maximum.log2)")
        }
        self.setup = setup
        realp = .allocate(capacity: half)
        realp.initialize(repeating: 0, count: half)
        imagp = .allocate(capacity: half)
        imagp.initialize(repeating: 0, count: half)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        realp.deinitialize(count: half); realp.deallocate()
        imagp.deinitialize(count: half); imagp.deallocate()
    }

    /// Raw one-sided DFT magnitudes |X[k]|, k = 0…N/2, of the N real samples at `input`.
    func rawMagnitudes(_ input: UnsafePointer<Float>, size: FFTSize, into output: UnsafeMutablePointer<Float>) {
        let m = size.rawValue / 2
        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        input.withMemoryRebound(to: DSPComplex.self, capacity: m) { packed in
            vDSP_ctoz(packed, 2, &split, 1, vDSP_Length(m))
        }
        vDSP_fft_zrip(setup, &split, 1, vDSP_Length(size.log2), FFTDirection(kFFTDirection_Forward))
        let dc = realp[0], nyquist = imagp[0]
        // Interior bins: |2·X[k]| for k = 1…M−1, then halved (exact).
        var interior = DSPSplitComplex(realp: realp + 1, imagp: imagp + 1)
        vDSP_zvabs(&interior, 1, output + 1, 1, vDSP_Length(m - 1))
        var halfScale: Float = 0.5
        vDSP_vsmul(output + 1, 1, &halfScale, output + 1, 1, vDSP_Length(m - 1))
        output[0] = abs(dc) * 0.5
        output[m] = abs(nyquist) * 0.5
    }
}
#endif
