// AppCoordinator+Slideshow.swift — the image slideshow's link to the Photo visual (MED-006-R3 to R9;
// research MED-006-D3, D4, D6; contracts/slideshow.md C4).
//
// * Content: while the slideshow is on and holds a slide, the photo layer shows its current slide;
//   otherwise MED-001's stored photo.
// * Tick: `PhotoVisualHost.beforeFrame` calls `slideshowTick()` once per drawn frame (so the slideshow
//   holds while paused, suspended, in the background or in Settings). Time is the monotonic clock the
//   tempo grid uses; the grid is passed only for a manual or stable tempo (Time rules otherwise); the
//   safety floor follows the effective sensory safety profile (Reduce flashing included). A due slide
//   becomes the content of this very frame (already decoded: a one-render cut), then the slide after it
//   is decoded ahead.
// * The slides are drawn by the same photo layer in the same compositor, so the composite flash guard
//   and the profile's envelope (`applyReduceFlashing`) see every frame.
import AudioCore
import Foundation
import ImageLayer

extension AppCoordinator {
    /// Wires the slideshow (called once in init).
    func connectSlideshow() {
        slideshow.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) }
        slideshow.onPlaybackChange = { [weak self] () -> Void in self?.refreshPhotoContent() }
        connectKenBurns()   // MED-007
    }

    /// What the photo layer shows: the slideshow's current slide when it is on, else the stored photo.
    var photoLayerContent: ImageLayerContent {
        if slideshow.isActive { return slideshow.currentURL.map { (url: URL) -> ImageLayerContent in .file(url) } ?? .none }
        return Self.photoContent(photos.photo)
    }

    /// Re-chooses the photo layer's content (a new photo, the slideshow started, stopped or was edited).
    func refreshPhotoContent() {
        guard let host = photoVisual else { return }
        host.content = photoLayerContent
        if let next = slideshow.nextURL { host.preload(next) }
        applyKenBurns()   // MED-007-R8: the slideshow started, stopped or was edited
    }

    /// MED-006-R7: the shortest time between two slide changes for the effective safety limits.
    var slideshowFloorNanoseconds: UInt64 {
        SlideshowSafetyFloor.nanoseconds(flashesPerSecond: settings.safetyClamp.limits.flashesPerSecond)
    }

    /// One frame of the Photo visual (before compositing).
    func slideshowTick() {
        guard slideshow.isActive, let host = photoVisual else { return }
        let grid: SlideshowBeatGrid? = currentSlideshowGrid
        if kenBurns.isEnabled { host.photo.kenBurnsDurationNanoseconds = kenBurnsDurationOverride(grid: grid) }   // MED-007-R8
        guard let url = slideshow.tick(now: MonotonicClock.nowNanoseconds(), grid: grid, floorNanoseconds: slideshowFloorNanoseconds) else { return }
        host.content = .file(url)
        if let next = slideshow.nextURL { host.preload(next) }
    }
}
