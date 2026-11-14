// AppCoordinator+MissingMedia.swift — MED-013 wiring (spec MED-013-R2, R4, R8): the Missing Media model
// reads the show's cues, announces on the library lane, adopts checksum matches after every photo and
// video import (chained after the existing change callbacks), and the placeholder follows each applied
// show scene (`applyShowScene`).
import Foundation
import SceneFormat
import ShowControl

extension AppCoordinator {
    /// Called once at the end of init, after the photo and video callbacks are set and the show exists.
    func connectMissingMedia(defaults: UserDefaults) {
        missingMedia.service = MediaRelinkService.makeDefault(defaults: defaults)
        missingMedia.cues = { [weak self] () -> ShowCueList in self?.show.list ?? ShowCueList() }
        missingMedia.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) }
        let photoChange = photos.onPhotoChange
        photos.onPhotoChange = { [weak self] (stored: StoredPhoto?) -> Void in
            photoChange?(stored)
            if stored != nil { self?.missingMedia.mediaImported() }
        }
        let videoChange = videos.onVideoChange
        videos.onVideoChange = { [weak self] (stored: StoredVideo?) -> Void in
            videoChange?(stored)
            if stored != nil { self?.missingMedia.mediaImported() }
        }
        #if DEBUG
        UITestMissingMediaFixture.seedIfRequested(self)   // MED-013: MissingMediaUITests
        #endif
    }

    /// MED-013-R2: the placeholder for a scene a show cue applied.
    func noteAppliedSceneMedia(_ document: SceneDocument, missingMedia missing: Bool) {
        missingMedia.sceneApplied(document, missingMedia: missing)
    }
}
