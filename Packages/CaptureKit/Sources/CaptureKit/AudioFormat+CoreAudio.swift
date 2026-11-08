// AudioFormat+CoreAudio.swift — map Core Audio stream descriptions to AudioFormat.
#if canImport(CoreAudioTypes)
import AudioCore
import CoreAudioTypes

extension AudioFormat {
    /// Linear PCM only (float32, int16, int32); anything else is unsupported (nil).
    public init?(asbd: AudioStreamBasicDescription) {
        guard asbd.mFormatID == kAudioFormatLinearPCM, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            return nil
        }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let sampleType: SampleType
        switch (isFloat, asbd.mBitsPerChannel) {
        case (true, 32): sampleType = .float32
        case (false, 16): sampleType = .int16
        case (false, 32): sampleType = .int32
        default: return nil
        }
        self.init(sampleRate: asbd.mSampleRate, channelCount: Int(asbd.mChannelsPerFrame),
                  isInterleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                  sampleType: sampleType)
    }
}
#endif
