// PhotosSaveStandIn.swift — DEBUG `-uitestPhotosAccess granted|denied|restricted|failing` (REC-011-R13,
// contract C5). Replaces Photos access and saving with in-memory fakes so UI tests never see iOS's prompt and
// nothing is written to the simulator's library. Release builds contain none of this.
#if DEBUG
import Foundation

@MainActor
final class PhotosSaveStandIn: PhotosAccessProviding, PhotosSaving {
    static let argument = "-uitestPhotosAccess"

    private let state: PhotosAccess
    private let failing: Bool

    init(state: PhotosAccess, failing: Bool) {
        self.state = state
        self.failing = failing
    }

    /// The stand-in the launch arguments ask for, if any.
    static func fromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> PhotosSaveStandIn? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "granted": return PhotosSaveStandIn(state: .granted, failing: false)
        case "denied": return PhotosSaveStandIn(state: .denied, failing: false)
        case "restricted": return PhotosSaveStandIn(state: .restricted, failing: false)
        case "failing": return PhotosSaveStandIn(state: .granted, failing: true)
        default: return nil
        }
    }

    func status() -> PhotosAccess { state }

    func request() async -> PhotosAccess { state }

    func save(_ item: PhotosSaveItem) async throws {
        if failing { throw CocoaError(.fileWriteUnknown) }
    }
}
#endif
