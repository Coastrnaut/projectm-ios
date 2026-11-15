// WaterfallHistoryTests.swift — VIS-020-T03, the roadmap acceptance ("Sixty seconds of input yields correct time order
// without texture growth"; VIS-020-R3, R4, R5, R8; S1, S2; contract C1). An injected clock and a synthetic input whose
// spectrum encodes time: of 128 bands, only band ⌊t⌋ (the second) is lit. After 60 s at 60 and at 24 frames per second
// the ring is exactly full and its rows, read oldest to newest, carry sequence numbers 0…511 and show their second's
// band in order; past 60 s the ring wraps and the order holds; storage never moves or grows. Plus the row mean, stalls,
// time running backwards, Reduce Motion and bad input. Pure Swift (Linux too).
import XCTest
@testable import VisualGenerators

final class WaterfallHistoryTests: XCTestCase {
    private static let bandCount = 128

    /// The input at time t: band ⌊t / 1 s⌋ at full level, the rest silent.
    private static func bands(at t: UInt64) -> [Float] {
        var b = [Float](repeating: 0, count: bandCount)
        b[Int(t / 1_000_000_000) % bandCount] = 1
        return b
    }

    private static func feed(_ history: SpectrumWaterfallHistory, frames: ClosedRange<Int>, fps: UInt64, reduceMotion: Bool = false) {
        for f in frames {
            let t: UInt64 = UInt64(f) * 1_000_000_000 / fps
            bands(at: t).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                history.advance(bands: b, timeNanoseconds: t, reduceMotion: reduceMotion)
            }
        }
    }

    /// The band whose column is brightest in the row `age` rows old.
    private static func dominantBand(_ h: SpectrumWaterfallHistory, age: Int) -> Int {
        var best = 0, bestLevel: UInt8 = 0
        for c in 0..<SpectrumWaterfallHistory.columns where h.level(column: c, age: age) > bestLevel {
            best = c
            bestLevel = h.level(column: c, age: age)
        }
        return Int((Float(best) * Float(bandCount - 1) / Float(SpectrumWaterfallHistory.columns - 1)).rounded())
    }

    /// Checks the whole ring, oldest to newest: consecutive sequences from `firstSequence`; a row inside one second
    /// shows that second's band; a row across a second boundary shows one of the two; the band never goes backwards.
    private func assertTimeOrder(_ h: SpectrumWaterfallHistory, firstSequence: Int, file: StaticString = #filePath, line: UInt = #line) {
        let rows: Int = SpectrumWaterfallHistory.rows
        let rowNs: Double = 60e9 / Double(rows)
        var previousBand = -1
        var inside = 0
        for age in stride(from: rows - 1, through: 0, by: -1) {
            let ring = try? XCTUnwrap(h.ringRow(age: age))
            let sequence: Int = h.sequence(ofRing: ring ?? 0)
            XCTAssertEqual(sequence, firstSequence + (rows - 1 - age), "age \(age)", file: file, line: line)
            let start: Double = Double(sequence) * rowNs, end: Double = Double(sequence + 1) * rowNs - 1
            let first = Int(start / 1e9), last = Int(end / 1e9)
            let band: Int = Self.dominantBand(h, age: age)
            if first == last {
                inside += 1
                XCTAssertEqual(band, first % Self.bandCount, "row \(sequence) lies in second \(first)", file: file, line: line)
            } else {
                XCTAssertTrue(band == first % Self.bandCount || band == last % Self.bandCount, "row \(sequence) straddles \(first)/\(last)",
                              file: file, line: line)
            }
            XCTAssertGreaterThanOrEqual(band, previousBand, "time order at row \(sequence)", file: file, line: line)
            previousBand = band
        }
        XCTAssertGreaterThan(inside, rows * 3 / 4, file: file, line: line)
    }

    func testSixtySecondsFillTheRingInTimeOrderAtAnyFrameRate() {
        for fps in [UInt64(60), 24] {
            let h = SpectrumWaterfallHistory()
            let address = UnsafeMutableRawPointer(h.levels)
            Self.feed(h, frames: 0...Int(60 * fps), fps: fps)   // the last frame is at exactly 60 s
            XCTAssertEqual(h.rowsWritten, SpectrumWaterfallHistory.rows, "60 s = 512 rows at \(fps) fps")
            assertTimeOrder(h, firstSequence: 0)
            XCTAssertEqual(Self.dominantBand(h, age: SpectrumWaterfallHistory.rows - 1), 0, "oldest: second 0")
            XCTAssertEqual(Self.dominantBand(h, age: 0), 59, "newest: second 59")
            XCTAssertEqual(UnsafeMutableRawPointer(h.levels), address, "storage never moves")
            XCTAssertEqual(SpectrumWaterfallHistory.byteCount, 131_072)
        }
    }

    func testPastSixtySecondsTheRingWrapsAndKeepsOrder() {
        let h = SpectrumWaterfallHistory()
        let address = UnsafeMutableRawPointer(h.levels)
        Self.feed(h, frames: 0...(75 * 30), fps: 30)
        XCTAssertEqual(h.rowsWritten, 640, "75 s = 640 rows")
        assertTimeOrder(h, firstSequence: 128)
        XCTAssertEqual(Self.dominantBand(h, age: SpectrumWaterfallHistory.rows - 1), 15, "oldest: second 15")
        XCTAssertEqual(Self.dominantBand(h, age: 0), 74)
        XCTAssertNil(h.ringRow(age: SpectrumWaterfallHistory.rows), "never more than 512 rows")
        XCTAssertEqual(UnsafeMutableRawPointer(h.levels), address)
        h.clear()
        XCTAssertEqual(UnsafeMutableRawPointer(h.levels), address, "a clear keeps the storage")
        XCTAssertEqual(h.rowsWritten, 0)
        XCTAssertEqual(h.level(column: 10, age: 0), 0)
    }

    func testARowIsTheMeanOfItsFramesAndColumnsFollowTheBands() {
        let h = SpectrumWaterfallHistory()
        func frame(_ v: Float, _ t: UInt64) {
            [v, v].withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in h.advance(bands: b, timeNanoseconds: t, reduceMotion: false) }
        }
        frame(0.2, 0)
        frame(0.6, 50_000_000)
        frame(1, 117_187_500)   // the first row ends: mean of 0.2 and 0.6
        XCTAssertEqual(h.rowsWritten, 1)
        XCTAssertEqual(h.level(column: 0, age: 0), 102)
        XCTAssertEqual(h.level(column: 255, age: 0), 102)
        // Two bands: a ramp from band 0 (left) to band 1 (right).
        [Float(0), 1].withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            h.advance(bands: b, timeNanoseconds: 234_375_000, reduceMotion: false)
        }
        XCTAssertEqual(h.level(column: 0, age: 0), 255, "the frame of 1.0 alone")
        [Float(0), 1].withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            h.advance(bands: b, timeNanoseconds: 351_562_500, reduceMotion: false)
        }
        XCTAssertEqual(h.level(column: 0, age: 0), 0)
        XCTAssertEqual(h.level(column: 255, age: 0), 255)
        XCTAssertEqual(h.level(column: 128, age: 0), SpectrumWaterfallHistory.quantize(128.0 / 255))
    }

    func testStallsHoldTheNewestLevelsAndTimeBackwardsWritesNothing() {
        let h = SpectrumWaterfallHistory()
        func frame(_ v: Float, _ t: UInt64) {
            [v].withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in h.advance(bands: b, timeNanoseconds: t, reduceMotion: false) }
        }
        frame(0.2, 0)
        frame(1, 1_000_000_000)   // rows 0…7 end: row 0 = the mean (0.2), rows 1…7 hold the newest frame
        XCTAssertEqual(h.rowsWritten, 8)
        XCTAssertEqual(h.level(column: 0, age: 7), SpectrumWaterfallHistory.quantize(0.2))
        for age in 0..<7 { XCTAssertEqual(h.level(column: 0, age: age), 255) }
        frame(0.5, 400_000_000)   // backwards: re-anchored, nothing written
        XCTAssertEqual(h.rowsWritten, 8)
        frame(0.5, 400_000_000 + 117_187_500)
        XCTAssertEqual(h.rowsWritten, 9, "one row after the new anchor")
        frame(0, 200_000_000_000)   // a 200 s stall: at most 512 rows
        XCTAssertEqual(h.rowsWritten, 9 + SpectrumWaterfallHistory.rows)
        for age in [0, 100, 510] { XCTAssertEqual(h.level(column: 3, age: age), 0, "the stall holds the newest level") }
        XCTAssertEqual(h.level(column: 3, age: 511), SpectrumWaterfallHistory.quantize(0.5), "the row before the stall is its mean")
    }

    func testReduceMotionHalvesTheScrollFromTheNextRow() {
        let calm = SpectrumWaterfallHistory()
        Self.feed(calm, frames: 0...3600, fps: 60, reduceMotion: true)
        XCTAssertEqual(calm.rowsWritten, 256, "60 s at half speed = half the ring")
        XCTAssertEqual(calm.rowNanoseconds, 234_375_000)
        let switched = SpectrumWaterfallHistory()
        Self.feed(switched, frames: 0...1800, fps: 60)
        XCTAssertEqual(switched.rowsWritten, 256)
        Self.feed(switched, frames: 1801...3600, fps: 60, reduceMotion: true)
        XCTAssertEqual(switched.rowsWritten, 256 + 128, "row 256 at the old step, then 234.375 ms rows")
        let sequences: [Int] = (0..<384).map { (age: Int) -> Int in switched.sequence(ofRing: switched.ringRow(age: age) ?? 0) }
        XCTAssertEqual(sequences, Array((0..<384).reversed()), "still in time order")
    }

    func testEmptyAndNonFiniteInputIsSilence() {
        let h = SpectrumWaterfallHistory()
        let empty: [Float] = []
        empty.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in h.advance(bands: b, timeNanoseconds: 0, reduceMotion: false) }
        [Float.nan, .infinity, 7, -3].withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            h.advance(bands: b, timeNanoseconds: 120_000_000, reduceMotion: false)
        }
        XCTAssertEqual(h.level(column: 0, age: 0), 0, "no bands = silence")
        [Float.nan, .infinity, 7, -3].withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            h.advance(bands: b, timeNanoseconds: 240_000_000, reduceMotion: false)
        }
        XCTAssertEqual(h.level(column: 0, age: 0), 0, "NaN → 0")
        XCTAssertEqual(h.level(column: 170, age: 0), 255, "7 clamps to full")
        XCTAssertEqual(h.level(column: 255, age: 0), 0, "−3 clamps to 0")
        XCTAssertEqual(SpectrumWaterfallHistory.quantize(.nan), 0)
    }

    func testPendingRowsListWhatWasWritten() {
        let h = SpectrumWaterfallHistory()
        var all = 0
        h.drainPending { (_: Int) -> Void in all += 1 }
        XCTAssertEqual(all, SpectrumWaterfallHistory.rows, "a new history uploads every row once")
        Self.feed(h, frames: 0...30, fps: 60)   // 0.5 s = rows 0…3
        var rows: [Int] = []
        h.drainPending { (r: Int) -> Void in rows.append(r) }
        XCTAssertEqual(rows, [0, 1, 2, 3])
        rows = []
        h.drainPending { (r: Int) -> Void in rows.append(r) }
        XCTAssertEqual(rows, [], "drained")
    }
}
