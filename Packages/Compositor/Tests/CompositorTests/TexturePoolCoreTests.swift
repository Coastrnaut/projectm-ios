// PERF-004-T02: the pool's bookkeeping with a fake resource and a fake GPU-completion fence (PERF-004-R1
// to R6, R10; S3, S4). Plain Swift: runs on the Mac host and in the Linux shape.
import Compositor
import XCTest

private final class FakeTexture {
    let name: String
    init(_ name: String) { self.name = name }
}

/// Stands for a command buffer: complete once the "GPU" finished it.
private final class FakeFence {
    var complete = false
}

final class TexturePoolCoreTests: XCTestCase {
    private typealias Core = TexturePoolCore<FakeTexture, FakeFence>

    private let small = TexturePoolKey(pixelFormat: 115, width: 64, height: 48, usage: 7, storageMode: 2, textureType: 2)
    private func key(width: Int = 64, height: Int = 48, format: UInt = 115, usage: UInt = 7) -> TexturePoolKey {
        TexturePoolKey(pixelFormat: format, width: width, height: height, usage: usage, storageMode: 2, textureType: 2)
    }

    private func makeCore(maxBytes: Int = 1_000, maxIdle: Int = 300) -> Core {
        Core(limits: TexturePoolLimits(maxRetiredBytes: maxBytes, maxIdleFrames: maxIdle)) { (fence: FakeFence) -> Bool in fence.complete }
    }

    /// Checks out `key`, creating (adopting) on a miss.
    private func take(_ core: inout Core, _ key: TexturePoolKey, bytes: Int = 100, name: String = "t") -> FakeTexture {
        if let reused = core.checkOut(key) { return reused }
        let made = FakeTexture(name)
        core.adopt(made, key: key, bytes: bytes)
        return made
    }

    private func assertInvariant(_ core: Core, file: StaticString = #filePath, line: UInt = #line) {
        let c = core.counters
        XCTAssertEqual(c.liveTextures, c.checkedOutTextures + c.retiredTextures, file: file, line: line)
        XCTAssertLessThanOrEqual(c.retiredBytes, core.limits.maxRetiredBytes, file: file, line: line)
        XCTAssertGreaterThanOrEqual(c.retiredTextures, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(c.waitingTextures, c.retiredTextures, file: file, line: line)
    }

    // MARK: - Keys (R1)

    func testOnlyAnIdenticalKeyIsReused() {
        var core = makeCore()
        let a = take(&core, small)
        core.checkIn(a, fence: nil)
        XCTAssertNil(core.checkOut(key(width: 65)), "another width misses")
        XCTAssertNil(core.checkOut(key(format: 70)), "another format misses")
        XCTAssertNil(core.checkOut(key(usage: 5)), "another usage misses")
        XCTAssertTrue(core.checkOut(small) === a, "the same key is reused")
        XCTAssertEqual(core.counters.hits, 1)
        XCTAssertEqual(core.counters.misses, 4, "the first take and three other keys")
        assertInvariant(core)
    }

    func testMostRecentlyReturnedIsReusedFirst() {
        var core = makeCore()
        let a = take(&core, small, name: "a"), b = take(&core, small, name: "b")
        core.checkIn(a, fence: nil)
        core.checkIn(b, fence: nil)
        XCTAssertTrue(core.checkOut(small) === b)
        XCTAssertTrue(core.checkOut(small) === a)
        XCTAssertNil(core.checkOut(small))
        assertInvariant(core)
    }

    // MARK: - Completion rule (R2, S3)

    func testNothingIsReusedBeforeItsFenceCompletes() {
        var core = makeCore()
        let a = take(&core, small)
        let fence = FakeFence()
        core.checkIn(a, fence: fence)
        XCTAssertEqual(core.counters.waitingTextures, 1)
        XCTAssertNil(core.checkOut(small), "the GPU may still use it")
        let b = take(&core, small, name: "b")
        XCTAssertFalse(a === b)
        fence.complete = true
        core.tick()
        XCTAssertEqual(core.counters.waitingTextures, 0)
        XCTAssertTrue(core.checkOut(small) === a, "reusable once its frame completed")
        assertInvariant(core)
    }

    func testANilFenceIsReusableAtOnceAndACompletedFenceToo() {
        var core = makeCore()
        let a = take(&core, small)
        core.checkIn(a, fence: nil)
        XCTAssertTrue(core.checkOut(small) === a)
        let done = FakeFence()
        done.complete = true
        core.checkIn(a, fence: done)
        XCTAssertEqual(core.counters.waitingTextures, 0)
        XCTAssertTrue(core.checkOut(small) === a)
    }

    // MARK: - Caps (R3, R4, S4)

    func testByteCapDropsTheLeastRecentlyReturnedFirst() {
        var core = makeCore(maxBytes: 250)
        let a = take(&core, small, name: "a"), b = take(&core, small, name: "b"), c = take(&core, small, name: "c")
        core.checkIn(a, fence: nil)
        core.checkIn(b, fence: nil)
        XCTAssertEqual(core.counters.retiredBytes, 200)
        core.checkIn(c, fence: nil)
        XCTAssertEqual(core.counters.retiredBytes, 200, "a was dropped")
        XCTAssertEqual(core.counters.evictions, 1)
        XCTAssertTrue(core.checkOut(small) === c)
        XCTAssertTrue(core.checkOut(small) === b)
        XCTAssertNil(core.checkOut(small), "a is gone")
        assertInvariant(core)
    }

    func testAnEntryLargerThanTheCapIsDroppedOnReturn() {
        var core = makeCore(maxBytes: 250)
        let big = take(&core, small, bytes: 300)
        XCTAssertTrue(core.checkIn(big, fence: nil))
        XCTAssertEqual(core.counters.retiredTextures, 0)
        XCTAssertEqual(core.counters.liveTextures, 0)
        XCTAssertEqual(core.counters.evictions, 1)
    }

    func testWaitingEntriesCountAgainstTheCapAndCanBeDropped() {
        var core = makeCore(maxBytes: 150)
        let a = take(&core, small, name: "a"), b = take(&core, small, name: "b")
        core.checkIn(a, fence: FakeFence())   // never completes
        core.checkIn(b, fence: nil)
        XCTAssertEqual(core.counters.retiredTextures, 1, "the waiting one was the oldest")
        XCTAssertTrue(core.checkOut(small) === b)
    }

    func testLoweringTheCapAppliesAtOnce() {
        var core = makeCore(maxBytes: 1_000)
        let a = take(&core, small), b = take(&core, small, name: "b")
        core.checkIn(a, fence: nil)
        core.checkIn(b, fence: nil)
        core.limits = TexturePoolLimits(maxRetiredBytes: 100, maxIdleFrames: 300)
        XCTAssertEqual(core.counters.retiredTextures, 1)
        assertInvariant(core)
    }

    func testIdleEntriesAreDroppedAfterTheAgeLimit() {
        var core = makeCore(maxIdle: 3)
        let a = take(&core, small)
        core.checkIn(a, fence: nil)
        for _ in 0..<3 { core.tick() }
        XCTAssertEqual(core.counters.retiredTextures, 1, "3 frames idle: kept")
        core.tick()
        XCTAssertEqual(core.counters.retiredTextures, 0, "4 frames idle: dropped")
        XCTAssertEqual(core.counters.evictions, 1)
        XCTAssertEqual(core.frame, 4)
        assertInvariant(core)
    }

    func testAReusedEntryStartsANewAge() {
        var core = makeCore(maxIdle: 2)
        let a = take(&core, small)
        core.checkIn(a, fence: nil)
        core.tick(); core.tick()
        XCTAssertTrue(core.checkOut(small) === a)
        core.tick(); core.tick()
        core.checkIn(a, fence: nil)
        core.tick(); core.tick()
        XCTAssertEqual(core.counters.retiredTextures, 1, "age counts from its last return")
    }

    // MARK: - Purge (R5)

    func testPurgeDropsIdleAndWaitingButNotCheckedOut() {
        var core = makeCore()
        let a = take(&core, small, name: "a"), b = take(&core, small, name: "b"), c = take(&core, small, name: "c")
        core.checkIn(a, fence: nil)
        core.checkIn(b, fence: FakeFence())
        core.purge()
        XCTAssertEqual(core.counters.retiredTextures, 0)
        XCTAssertEqual(core.counters.retiredBytes, 0)
        XCTAssertEqual(core.counters.purged, 2)
        XCTAssertEqual(core.counters.purges, 1)
        XCTAssertEqual(core.counters.checkedOutTextures, 1)
        XCTAssertTrue(core.isCheckedOut(c))
        XCTAssertTrue(core.checkIn(c, fence: nil), "a checked-out texture can still come back")
        assertInvariant(core)
    }

    // MARK: - Robustness and counters (R6)

    func testUnknownAndDoubleCheckInsAreIgnored() {
        var core = makeCore()
        XCTAssertFalse(core.checkIn(FakeTexture("stranger"), fence: nil))
        let a = take(&core, small)
        XCTAssertTrue(core.checkIn(a, fence: nil))
        XCTAssertFalse(core.checkIn(a, fence: nil), "already retired")
        XCTAssertEqual(core.counters.retiredTextures, 1)
        core.adopt(a, key: small, bytes: 100)
        XCTAssertEqual(core.counters.liveTextures, 1, "adopting a retired texture again changes nothing")
        assertInvariant(core)
    }

    func testCountersFollowAMixedSequence() {
        var core = makeCore(maxBytes: 300, maxIdle: 5)
        var held: [FakeTexture] = []
        for round in 0..<20 {
            let k = round % 3 == 0 ? key(width: 32) : small
            held.append(take(&core, k, name: "r\(round)"))
            if held.count > 2 { core.checkIn(held.removeFirst(), fence: round % 2 == 0 ? FakeFence() : nil) }
            core.tick()
            assertInvariant(core)
        }
        XCTAssertEqual(core.counters.checkedOutTextures, 2)
        XCTAssertEqual(core.counters.hits + core.counters.misses, 20)
    }

    func testDefaultLimits() {
        XCTAssertEqual(TexturePoolLimits.default(recommendedWorkingSetBytes: 0).maxRetiredBytes, 128 << 20)
        XCTAssertEqual(TexturePoolLimits.default(recommendedWorkingSetBytes: 512 << 20).maxRetiredBytes, 64 << 20, "an eighth")
        XCTAssertEqual(TexturePoolLimits.default(recommendedWorkingSetBytes: 8 << 30).maxRetiredBytes, 128 << 20, "at most 128 MiB")
        XCTAssertEqual(TexturePoolLimits().maxIdleFrames, 300)
        XCTAssertEqual(TexturePoolLimits(maxRetiredBytes: -5, maxIdleFrames: -1), TexturePoolLimits(maxRetiredBytes: 0, maxIdleFrames: 0))
    }
}
