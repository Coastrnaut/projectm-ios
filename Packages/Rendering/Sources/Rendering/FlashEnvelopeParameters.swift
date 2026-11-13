// FlashEnvelopeParameters.swift — the strobe safety envelope's limits for CFlashLimiter's GPU port
// (FX-019, ADR-0011; contracts/flash-envelope.md).
import CFlashLimiter
import FlashSafety

extension FlashEnvelopeConfiguration {
    /// One frame's parameters for `PMFlashLimiterFinish`; the frame time is clamped here.
    public func limiterParameters(frameTime: Double) -> PMFlashEnvelopeParameters {
        PMFlashEnvelopeParameters(frameTime: Float(clampedFrameTime(frameTime)), window: Float(window),
                                  luminanceThreshold: Float(luminanceThreshold), rednessThreshold: Float(rednessThreshold),
                                  gateMargin: Float(gateMargin), riseRatePerSecond: Float(riseRatePerSecond ?? -1),
                                  transitionBudget: Int32(transitionBudget))
    }
}
