// MOD-001-T11: current manual values (MOD-001-R7, R8; S5; contract C3). Deterministic: observers are
// synchronous, the concurrency check asserts counts only, never timing.
import ParameterGraph
import Synchronization
import XCTest

/// Collects changes from any thread.
final class ChangeLog: Sendable {
    private let entries = Mutex<[ParameterChange]>([])
    func append(_ change: ParameterChange) { entries.withLock { $0.append(change) } }
    var all: [ParameterChange] { entries.withLock { $0 } }
}

func makeStoreRegistry() throws -> ParameterRegistry {
    try ParameterRegistry(descriptors: [
        continuous("t.level", step: 0.1),
        descriptor("t.count", .integer(minimum: 0, maximum: 10, defaultValue: 4, step: 2)),
        descriptor("t.odd", .integer(minimum: 0, maximum: 9, defaultValue: 0, step: 2)),
        descriptor("t.on", .boolean(defaultValue: false)),
        descriptor("t.orientation", .enumeration(cases: sampleCases, defaultValue: "vertical")),
        descriptor("t.tint", .color(defaultValue: ParameterColor(red: 0, green: 0, blue: 0, alpha: 1))),
    ])
}

final class ParameterStoreTests: XCTestCase {
    func testStartsAtDefaults() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        XCTAssertEqual(store.double("t.level"), 0.5)
        XCTAssertEqual(store.int("t.count"), 4)
        XCTAssertEqual(store.bool("t.on"), false)
        XCTAssertEqual(store.enumCase("t.orientation"), "vertical")
        XCTAssertEqual(store.color("t.tint"), ParameterColor(red: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(store.changeCount, 0)
        XCTAssertNil(store.value(for: "t.missing"))
    }

    func testContinuousClampsWithoutSnappingAndNotifies() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        let log = ChangeLog()
        let observation = store.observe { log.append($0) }
        XCTAssertEqual(try store.setDouble(1.5, for: "t.level"), 1)
        XCTAssertEqual(log.all, [ParameterChange(id: "t.level", oldValue: .continuous(0.5), newValue: .continuous(1), changeCount: 1)])
        XCTAssertEqual(try store.setDouble(-0.5, for: "t.level"), 0)
        XCTAssertEqual(try store.setDouble(0.123, for: "t.level"), 0.123) // the 0.1 step is a hint only
        XCTAssertEqual(try store.setDouble(.infinity.nextDown, for: "t.level"), 1)
        XCTAssertEqual(store.changeCount, 4)
        // Equal value: stored, no notification.
        XCTAssertEqual(try store.setDouble(1, for: "t.level"), 1)
        XCTAssertEqual(store.changeCount, 4)
        XCTAssertEqual(log.all.count, 4)
        observation.cancel()
    }

    func testIntegerSnapsToStepThenClamps() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        XCTAssertEqual(try store.setInt(3, for: "t.count"), 4)   // tie between 2 and 4 → toward the maximum
        XCTAssertEqual(try store.setInt(5, for: "t.count"), 6)
        XCTAssertEqual(try store.setInt(7, for: "t.count"), 8)
        XCTAssertEqual(try store.setInt(11, for: "t.count"), 10)
        XCTAssertEqual(try store.setInt(-3, for: "t.count"), 0)
        XCTAssertEqual(try store.setInt(.max, for: "t.count"), 10)
        XCTAssertEqual(try store.setInt(9, for: "t.odd"), 8)     // the maximum 9 is off the grid: the last step wins
    }

    func testColorClampsPerComponent() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        let stored = try store.setColor(ParameterColor(red: 1.5, green: -1, blue: 0.25, alpha: 2), for: "t.tint")
        XCTAssertEqual(stored, ParameterColor(red: 1, green: 0, blue: 0.25, alpha: 1))
        XCTAssertEqual(store.color("t.tint"), stored)
    }

    func testInvalidSetsAreRejectedWithoutSideEffects() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        let log = ChangeLog()
        let observation = store.observe { log.append($0) }
        let attempts: [(ParameterValue, ParameterID, ParameterStoreError)] = [
            (.continuous(.nan), "t.level", .nonFiniteValue("t.level")),
            (.continuous(.infinity), "t.level", .nonFiniteValue("t.level")),
            (.continuous(-.infinity), "t.level", .nonFiniteValue("t.level")),
            (.integer(1), "t.level", .kindMismatch("t.level", expected: "continuous", got: "integer")),
            (.boolean(true), "t.orientation", .kindMismatch("t.orientation", expected: "enum", got: "boolean")),
            (.enumeration("diagonal"), "t.orientation", .unknownEnumCase("t.orientation", "diagonal")),
            (.color(ParameterColor(red: .nan, green: 0, blue: 0)), "t.tint", .nonFiniteValue("t.tint")),
            (.continuous(0.2), "t.missing", .unknownParameter("t.missing")),
        ]
        for (value, id, expected) in attempts {
            XCTAssertThrowsError(try store.set(value, for: id)) { error in
                XCTAssertEqual(error as? ParameterStoreError, expected)
                XCTAssertTrue("\(error)".contains(id.rawValue), "\(error)")
            }
        }
        XCTAssertEqual(store.changeCount, 0)
        XCTAssertTrue(log.all.isEmpty)
        for d in store.registry.descriptors { XCTAssertEqual(store.value(for: d.id), d.defaultValue, "\(d.id)") }
        observation.cancel()
    }

    func testTypedAccessorsRoundTripAndRejectOtherKinds() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        try store.setDouble(0.25, for: "t.level")
        try store.setInt(6, for: "t.count")
        try store.setBool(true, for: "t.on")
        try store.setEnumCase("horizontal", for: "t.orientation")
        try store.setColor(ParameterColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4), for: "t.tint")
        XCTAssertEqual(store.double("t.level"), 0.25)
        XCTAssertEqual(store.int("t.count"), 6)
        XCTAssertEqual(store.bool("t.on"), true)
        XCTAssertEqual(store.enumCase("t.orientation"), "horizontal")
        XCTAssertEqual(store.color("t.tint"), ParameterColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
        XCTAssertNil(store.double("t.count"))
        XCTAssertNil(store.int("t.level"))
        XCTAssertNil(store.bool("t.orientation"))
        XCTAssertNil(store.enumCase("t.on"))
        XCTAssertNil(store.color("t.level"))

        enum Orientation: String { case vertical, horizontal }
        XCTAssertEqual(store.enumValue(Orientation.self, for: "t.orientation"), .horizontal)
        try store.setEnum(Orientation.vertical, for: "t.orientation")
        XCTAssertEqual(store.enumCase("t.orientation"), "vertical")
    }

    func testResetAndResetAll() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        try store.setDouble(0.9, for: "t.level")
        try store.setBool(true, for: "t.on")
        try store.reset("t.level")
        XCTAssertEqual(store.double("t.level"), 0.5)
        XCTAssertThrowsError(try store.reset("t.missing"))
        store.resetAll()
        XCTAssertEqual(store.bool("t.on"), false)
        XCTAssertEqual(store.changeCount, 4)
    }

    func testObserverOrderCancellationAndReentrantReads() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        let order = Mutex<[String]>([])
        let first = store.observe { change in
            // Reading the store inside an observer must not deadlock: the lock is already released.
            let current = store.double(change.id)
            order.withLock { $0.append("first \(current ?? -1)") }
        }
        let second = store.observe { _ in order.withLock { $0.append("second") } }
        try store.setDouble(0.75, for: "t.level")
        XCTAssertEqual(order.withLock { $0 }, ["first 0.75", "second"])
        first.cancel()
        first.cancel() // idempotent
        try store.setDouble(0.25, for: "t.level")
        XCTAssertEqual(order.withLock { $0 }, ["first 0.75", "second", "second"])
        second.cancel()
        try store.setDouble(0.3, for: "t.level")
        XCTAssertEqual(order.withLock { $0 }.count, 3)
    }

    func testConcurrentSetsCountEveryEffectiveChange() async throws {
        let ids: [ParameterID] = ["c.a", "c.b", "c.c", "c.d"]
        let store = ParameterStore(registry: try ParameterRegistry(descriptors: ids.map { continuous($0) }))
        let log = ChangeLog()
        let observation = store.observe { log.append($0) }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    for k in 1...250 { _ = try? store.setDouble(Double(k) * 0.001, for: id) }
                }
            }
        }
        XCTAssertEqual(store.changeCount, 1_000)
        XCTAssertEqual(log.all.count, 1_000)
        XCTAssertEqual(Set(log.all.map(\.changeCount)).count, 1_000)
        for id in ids { XCTAssertEqual(store.double(id) ?? 0, 0.25, accuracy: 1e-12) }
        observation.cancel()
    }
}
