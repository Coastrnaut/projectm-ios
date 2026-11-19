// UITestMediaDeviceProbes.swift — DEBUG only (QA-011 device automation, Batch 5: media layers). Two readouts for
// the device tests in Apps/projectM-iOS/DeviceUITests/B07MediaDeviceTests.swift and B13MediaDeviceTests.swift,
// shown with `-uitestDiagnostics` (MediaProbes, VisualizerView):
// * `videoFrameRate` (MED-002-T27, MED-004-T22): the video layer's distinct pictures per second over the last
//   second, from its pipeline counters (`taken`: became the shown picture; `dropped`: removed late), as
//   "fps=<x.x> late=<n> taken=<total> dropped=<total>"; "fps=none" until two samples. The frame loop's own rate
//   is the performance overlay's; this is the clip's.
// * `photoStoredMetadata` (MED-001-T24): what ImageIO reads from the stored copy of the photo, as
//   "gps=<none|present> exif=<none|present> size=<w>x<h> bytes=<n>" ("none" with no photo). The import strips the
//   location (MED-001-R6); this shows the copy the app keeps, not the picked file.
// Nothing here changes what the app does. Not compiled into Release builds.
#if DEBUG
import Foundation
import ImageIO
import SwiftUI

struct MediaDeviceProbes: View {
    let coordinator: AppCoordinator

    var body: some View {
        if let video = coordinator.videoVisual { VideoRateProbe(video: video) }
        PhotoMetadataProbe(photos: coordinator.photos)
    }
}

/// Distinct video pictures per second (see the file comment).
@MainActor
final class VideoRateSampler {
    private var last: (time: Double, taken: Int, dropped: Int)?
    private var text = "fps=none"

    func sample(_ video: VideoVisualHost) -> String {
        let now = ProcessInfo.processInfo.systemUptime
        let stats = video.video.statistics
        guard let previous = last else {
            last = (now, stats.taken, stats.dropped)
            return text
        }
        let elapsed = now - previous.time
        guard elapsed >= 0.9 else { return text }   // the timeline can redraw more often than once a second
        let fps = Double(max(0, stats.taken - previous.taken)) / elapsed
        let late = max(0, stats.dropped - previous.dropped)
        text = "fps=" + String(format: "%.1f", fps) + " late=" + String(late) + " taken=" + String(stats.taken)
            + " dropped=" + String(stats.dropped)
        last = (now, stats.taken, stats.dropped)
        return text
    }
}

struct VideoRateProbe: View {
    let video: VideoVisualHost
    @State private var sampler = VideoRateSampler()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let text: String = sampler.sample(video)
            Text(text)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("videoFrameRate")
                .accessibilityValue(text)
        }
    }
}

struct PhotoMetadataProbe: View {
    let photos: PhotoCoordinator

    var body: some View {
        let text: String = Self.describe(photos.photo?.url)
        Text(text)
            .font(.caption2)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("photoStoredMetadata")
            .accessibilityValue(text)
    }

    static func describe(_ url: URL?) -> String {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return "none" }
        let gps = properties[kCGImagePropertyGPSDictionary] == nil ? "none" : "present"
        let exif = properties[kCGImagePropertyExifDictionary] == nil ? "none" : "present"
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? -1
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? -1
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        return "gps=\(gps) exif=\(exif) size=\(width)x\(height) bytes=\(bytes)"
    }
}
#endif
