// ShowRehearsalTarget.swift — SHOW-006 which cue cue rehearsal previews (specs/237-show-006-cue-rehearsal; R2;
// data-model.md; research SHOW-006-D7).
//
// * `.followNext` previews the cue Next would reach (SHOW-005: skipped cues passed over) and so follows the show.
// * `.picked(cueID)` is a cue the performer chose with the rehearsal's arrows: any cue, skipped ones included (as Go
//   to Cue reaches them). A picked cue that is no longer in the list falls back to the next cue.
// * Pure: resolving and stepping read the list and never change it (the show's position never moves).
import Foundation

public enum ShowRehearsalTarget: Sendable, Hashable {
    case followNext
    case picked(UUID)

    /// The cue to preview, or nil (no next cue: end of show, empty or every later cue skipped).
    public func resolve(in list: ShowCueList) -> ShowCue? {
        switch self {
        case .followNext:
            return list.nextCue
        case let .picked(id):
            return list.cues.first { (cue: ShowCue) -> Bool in cue.id == id } ?? list.nextCue
        }
    }

    /// The cue `delta` places from the resolved one (clamped to the list). Without a resolved cue, forward picks the
    /// last cue and back picks the last cue too (the end of the show is after it). An empty list keeps the target.
    public func stepped(by delta: Int, in list: ShowCueList) -> ShowRehearsalTarget {
        guard !list.cues.isEmpty else { return self }
        let current: Int
        if let cue = resolve(in: list), let index = list.cues.firstIndex(where: { (c: ShowCue) -> Bool in c.id == cue.id }) {
            current = index
        } else {
            current = list.cues.count   // past the last cue
        }
        let target: Int = min(max(current + delta, 0), list.cues.count - 1)
        return .picked(list.cues[target].id)
    }
}
