// VideoContainerCheck.swift — the container check of a movie before AVFoundation opens it
// (MED-014-R7, R8; research MED-014-D2, D5; contracts/safe-decoder.md). Plain Swift, every platform.
//
// `MovieContainerSniffer` walks the file's boxes through a `FileByteSource` (headers and two small
// boxes only, never the whole file) and the outcome maps to the typed import errors: not a movie
// container → `.notAVideo`; a box past the end, a missing or second `moov`, a walk bound exceeded →
// `.damaged`; no video track → `.notAVideo`; a coded picture longer than `maxLongestSide` →
// `.pictureTooLarge`; a read error → `.unreadable`. AVFoundation's own checks (MED-002-R5) follow.
// Used by the import probe and before every open of the playback reader (start, loop, seek).
import Foundation
import MediaSniffing

public enum VideoContainerCheck {
    /// Checks the movie at `url`; returns the container's facts.
    @discardableResult
    public static func check(_ url: URL, limits: VideoImportLimits) throws(VideoImportError) -> MovieContainerFacts {
        let source: FileByteSource
        do throws(MediaSniffError) {
            source = try FileByteSource(url: url)
        } catch {
            throw map(error)
        }
        return try check(source, limits: limits)
    }

    /// Checks movie bytes from any source.
    @discardableResult
    public static func check(_ source: some ByteSource, limits: VideoImportLimits) throws(VideoImportError) -> MovieContainerFacts {
        let facts: MovieContainerFacts
        do throws(MediaSniffError) {
            facts = try MovieContainerSniffer.sniff(source)
        } catch {
            throw map(error)
        }
        guard facts.videoTrackCount > 0 else { throw .notAVideo }
        guard max(facts.codedWidth, facts.codedHeight) <= limits.maxLongestSide else { throw .pictureTooLarge }
        return facts
    }

    static func map(_ error: MediaSniffError) -> VideoImportError {
        switch error {
        case .empty, .unrecognized: .notAVideo
        case .truncated, .corrupt: .damaged
        case .unreadable: .unreadable
        }
    }
}
