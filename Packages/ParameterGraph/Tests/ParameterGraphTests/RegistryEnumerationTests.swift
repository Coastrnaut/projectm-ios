// MOD-001-T07: deterministic enumeration and lookup (MOD-001-R6, S4; contract C2.3).
import ParameterGraph
import XCTest

final class RegistryEnumerationTests: XCTestCase {
    private let ring = ParameterGroup(id: "visual.ring", displayName: "Ring")
    private let glow = ParameterGroup(id: "effect.glow", displayName: "Glow")

    private func makeDescriptors() -> [ParameterDescriptor] {
        [continuous("visual.ring.size", group: ring),
         continuous("effect.glow.amount", group: glow),
         continuous("visual.ring.gap", group: ring),
         descriptor("effect.glow.on", .boolean(defaultValue: false), group: glow),
         continuous("visual.ring.angle", group: ring)]
    }

    func testEnumerationFollowsRegistrationOrderAndRepeats() throws {
        let registry = try ParameterRegistry(descriptors: makeDescriptors())
        let expected: [ParameterID] = ["visual.ring.size", "effect.glow.amount", "visual.ring.gap", "effect.glow.on", "visual.ring.angle"]
        XCTAssertEqual(registry.ids, expected)
        XCTAssertEqual(registry.ids, registry.ids)
        XCTAssertEqual(try ParameterRegistry(descriptors: makeDescriptors()).ids, expected)
        XCTAssertEqual(registry.groups.map(\.id), ["visual.ring", "effect.glow"])
        XCTAssertEqual(registry.descriptors(inGroup: "visual.ring").map(\.id), ["visual.ring.size", "visual.ring.gap", "visual.ring.angle"])
        XCTAssertEqual(registry.descriptors(inGroup: "effect.glow").map(\.id), ["effect.glow.amount", "effect.glow.on"])
        XCTAssertTrue(registry.descriptors(inGroup: "nothing").isEmpty)
    }

    func testLookup() throws {
        let registry = try ParameterRegistry(descriptors: makeDescriptors())
        XCTAssertEqual(registry.descriptor(for: "visual.ring.gap")?.displayName, "Level")
        XCTAssertEqual(registry.descriptor(for: "effect.glow.on")?.defaultValue, .boolean(false))
        XCTAssertNil(registry.descriptor(for: "visual.ring.missing"))
        XCTAssertFalse(registry.contains("visual.ring.missing"))
        XCTAssertEqual(registry.count, 5)
    }
}
