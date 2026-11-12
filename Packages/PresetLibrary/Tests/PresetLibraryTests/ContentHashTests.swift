// PRE-012-T02: the package's own SHA-1 and SHA-256 (research D3) against published vectors.
import XCTest
@testable import PresetLibrary

final class ContentHashTests: XCTestCase {
    private func a(_ count: Int) -> [UInt8] { [UInt8](repeating: 0x61, count: count) }

    func testSHA256Vectors() {
        XCTAssertEqual(ContentHash.sha256Hex([]), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(ContentHash.sha256Hex(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(ContentHash.sha256Hex(a(1_000_000)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testSHA1Vectors() {
        XCTAssertEqual(ContentHash.sha1Hex([]), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(ContentHash.sha1Hex(Array("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(ContentHash.sha1Hex(a(1_000_000)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
    }

    func testPaddingBoundaries() {
        let expected: [(Int, String, String)] = [
            (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318", "c1c8bbdc22796e28c0e15163d20899b65621d65a"),
            (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a", "c2db330f6083854c99d4b5bfb6e8f29f201be699"),
            (63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34", "03f09f5b158a7a8cdad920bddc29b81c18a551f5"),
            (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb", "0098ba824b5c16427bd7a1122a5a442a25ec644d"),
            (65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0", "11655326c708d70319be2610e8a57d9a5b959d3b"),
        ]
        for (count, sha256, sha1) in expected {
            XCTAssertEqual(ContentHash.sha256Hex(a(count)), sha256, "\(count)")
            XCTAssertEqual(ContentHash.sha1Hex(a(count)), sha1, "\(count)")
        }
    }

    /// The id `git hash-object` prints: what the built-in index and the takedown list hold.
    func testGitBlobHash() {
        XCTAssertEqual(ContentHash.gitBlobSHA1Hex(Array("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }
}
