// VideoToolboxEncoderCapabilities.swift — REC-005 the real capability source (research REC-005-D2).
//
// Asks VideoToolbox (public `VTCopySupportedPropertyDictionaryForEncoder`) whether an encoder exists for a
// codec at an exact size; `noErr` means yes. Answers are cached per codec and size (a query takes a few
// milliseconds; it never runs in the frame loop). The display's frame rate is given by the app
// (`UIScreen.maximumFramesPerSecond`). The writer's `canApply` stays the final gate at Record.
#if canImport(VideoToolbox) && canImport(CoreMedia)
import CoreMedia
import Synchronization
import VideoToolbox

public final class VideoToolboxEncoderCapabilities: RecordingEncoderCapabilities, @unchecked Sendable {
    private struct Key: Hashable {
        let codec: RecordingCodec
        let width: Int
        let height: Int
    }

    public let maxFramesPerSecond: Int
    private let cache = Mutex<[Key: Bool]>([:])

    public init(maxFramesPerSecond: Int = 60) {
        self.maxFramesPerSecond = max(maxFramesPerSecond, 1)
    }

    public func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool {
        let key = Key(codec: codec, width: width, height: height)
        if let known = cache.withLock({ (c: inout [Key: Bool]) -> Bool? in c[key] }) { return known }
        let answer: Bool = Self.query(codec, width: width, height: height)
        cache.withLock { (c: inout [Key: Bool]) -> Void in c[key] = answer }
        return answer
    }

    static func query(_ codec: RecordingCodec, width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max) else { return false }
        let type: CMVideoCodecType = codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        var properties: CFDictionary?
        let status = VTCopySupportedPropertyDictionaryForEncoder(width: Int32(width), height: Int32(height), codecType: type,
                                                                 encoderSpecification: nil, encoderIDOut: nil,
                                                                 supportedPropertiesOut: &properties)
        return status == noErr
    }
}
#endif
