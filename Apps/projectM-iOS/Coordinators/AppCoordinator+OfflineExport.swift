// AppCoordinator+OfflineExport.swift — REC-013: the offline export's link to the app
// (specs/240-rec-013-deterministic-offline-export; R1, R11, R13).
//
// * The export reads the live settings (never writes them), saves to Photos through REC-011's coordinator and
//   announces on the library lane (ACC-004). DEBUG: `-uitestOfflineExportSeconds <s>` shortens the fixture for the UI test.
import Foundation

extension AppCoordinator {
    func connectOfflineExport() {
        offlineExport.connect(settings: settings, photos: photosSave,
                              announce: { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) })
        #if DEBUG
        let seconds: Double = UserDefaults.standard.double(forKey: "uitestOfflineExportSeconds")
        if seconds > 0 { offlineExport.fixtureSeconds = seconds }
        #endif
    }
}
