// HelpLibraryTests.swift — UIX-014-T06, T07 (UIX-014-S1, S2, S4; contract contracts/help-content.md).
//
// The roadmap acceptance "All help articles open with airplane mode enabled", proved structurally on the simulator
// (research UIX-014-D6): every index entry is in the built app bundle and opens through the browser's model with a
// title heading and a body; no article holds a link or address; the help sources use no networking or web API.
// The built app's network scan (scripts/check_network_symbols.py) is the fourth proof. Airplane Mode on D1 is the
// `{device}` task UIX-014-T12.
import XCTest
@testable import projectM_iOS

final class HelpLibraryTests: XCTestCase {
    private func library() throws -> HelpLibrary {
        try XCTUnwrap(HelpLibrary.bundled(), "Help/index.json is in the app bundle")
    }

    func testEveryIndexedArticleIsBundledAndOpensWithItsTitleAndBody() throws {
        let library = try library()
        XCTAssertEqual(library.entries.count, 11)
        XCTAssertEqual(Set(library.entries.map(\.id)).count, library.entries.count, "ids are unique")
        for entry in library.entries {
            XCTAssertNotNil(Bundle.main.url(forResource: (entry.file as NSString).deletingPathExtension, withExtension: "md",
                                            subdirectory: HelpLibrary.folder), "\(entry.file) is in the built bundle")
            let article = try XCTUnwrap(library.article(for: entry), "\(entry.id) opens")
            XCTAssertEqual(article.blocks.first, .heading(level: 1, text: entry.title), entry.id)
            XCTAssertGreaterThan(article.blocks.count, 3, "\(entry.id) has a body")
            for block in article.blocks {
                let text: String
                switch block {
                case let .heading(_, value), let .paragraph(value), let .bullet(value), let .numbered(_, value): text = value
                }
                XCTAssertFalse(HelpMarkdown.inline(text).characters.isEmpty, "\(entry.id): a block renders text")
            }
            XCTAssertGreaterThanOrEqual(entry.keywords.count, 3, "\(entry.id) keywords")
        }
    }

    func testNoArticleHasALinkAnAddressUnsupportedSyntaxOrANamedService() throws {
        let library = try library()
        for entry in library.entries {
            let text = try XCTUnwrap(library.text(for: entry), entry.id)
            XCTAssertEqual(HelpContentRules.violations(in: text, title: entry.title), [], entry.id)
        }
    }

    func testRulesCatchLinksAddressesNamesAndLength() {
        let base = "# Title\n\nBody.\n"
        XCTAssertEqual(HelpContentRules.violations(in: base, title: "Title"), [])
        XCTAssertFalse(HelpContentRules.violations(in: base + "See https://example.com", title: "Title").isEmpty)
        XCTAssertFalse(HelpContentRules.violations(in: base + "[here](x)", title: "Title").isEmpty)
        XCTAssertFalse(HelpContentRules.violations(in: base + "Write to mailto:a", title: "Title").isEmpty)
        XCTAssertFalse(HelpContentRules.violations(in: base + "Works with Spotify.", title: "Title").isEmpty)
        XCTAssertFalse(HelpContentRules.violations(in: base + "| a | b |", title: "Title").isEmpty)
        XCTAssertFalse(HelpContentRules.violations(in: base + String(repeating: "word ", count: 400), title: "Title").isEmpty)
        XCTAssertFalse(HelpContentRules.violations(in: base, title: "Other").isEmpty, "title must match")
    }

    func testParserReadsTheSubset() {
        let blocks = HelpMarkdown.parse("""
        # Top

        One line
        continues **here**.

        ## Part
        - first *item*
        - second
        1. step one
        12. step twelve
        ### Small
        #NotAHeading
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Top"),
            .paragraph("One line continues **here**."),
            .heading(level: 2, text: "Part"),
            .bullet("first *item*"),
            .bullet("second"),
            .numbered(1, "step one"),
            .numbered(12, "step twelve"),
            .heading(level: 3, text: "Small"),
            .paragraph("#NotAHeading"),
        ])
        XCTAssertEqual(String(HelpMarkdown.inline("continues **here**.").characters), "continues here.")
    }

    func testSearchMatchesTitlesAndKeywordsIgnoringCaseAndAccents() throws {
        let library = try library()
        XCTAssertEqual(library.search("").map(\.id), library.entries.map(\.id), "empty query: all, in index order")
        XCTAssertEqual(library.search("  ").count, library.entries.count)
        XCTAssertEqual(library.search("MIDI").map(\.id), ["midi-osc"])
        XCTAssertTrue(library.search("flash").map(\.id).contains("accessibility-safety"))
        XCTAssertTrue(library.search("prívacy").map(\.id).contains("privacy"), "accent-insensitive")
        XCTAssertTrue(library.search("projector").map(\.id).contains("external-display"), "keyword match")
        XCTAssertEqual(library.search("zzzz"), [])
    }

    func testMissingFileAndMissingIndexGiveNil() throws {
        let library = try library()
        let ghost = HelpEntry(id: "ghost", title: "Ghost", file: "ghost.md", keywords: [])
        XCTAssertNil(library.article(for: ghost))
        XCTAssertNil(HelpLibrary.bundled(Bundle(for: HelpLibraryTests.self)), "the test bundle has no help index")
    }

    /// UIX-014-R6: the help code path references no networking or web API (the built-app scan covers the binary).
    func testHelpSourcesUseNoNetworkingOrWebAPI() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = ["Coordinators/HelpLibrary.swift", "Views/HelpBrowserView.swift"]
        // Split literals: scripts/check_compliance.py scans test sources too, and these names must not appear whole.
        let parts: [[String]] = [["URL", "Session"], ["URL", "Request"], ["WK", "WebView"], ["Web", "Kit"],
                                 ["SFSafari", "ViewController"], ["Safari", "Services"], ["open", "URL"],
                                 ["Link(", "destination"], ["import ", "Network"], ["NW", "Connection"],
                                 ["UIApplication.shared", ".open"], ["URL(", "string:"]]
        let forbidden: [String] = parts.map { (pieces: [String]) -> String in pieces.joined() }
        for file in files {
            let source = try String(contentsOf: app.appendingPathComponent(file), encoding: .utf8)
            for symbol in forbidden { XCTAssertFalse(source.contains(symbol), "\(file) mentions \(symbol)") }
        }
    }
}
