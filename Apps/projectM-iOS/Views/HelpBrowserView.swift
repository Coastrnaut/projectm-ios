// HelpBrowserView.swift — UIX-014: Settings › Help (specs/302-uix-014-offline-help-browser; contract
// contracts/help-content.md, UI identifiers).
//
// * `HelpSection`: the Settings row "Help" (`helpLink`), in `SettingsView.tailSections` outside the scene-lock-disabled
//   sections (Help changes nothing).
// * `HelpBrowserView`: the article list in index order with a search field over titles and keywords; "No help
//   articles match" when nothing matches; "Help is not available." when the index is missing.
// * `HelpArticleView`: one article, each block a `Text` with a Dynamic Type text style; headings carry the header trait
//   (UIX-014-R7). Inline emphasis only; articles hold no links, so nothing here can open or load anything (R5, R6).
// Everything comes from the app bundle; nothing is stored (R10).
import SwiftUI

struct HelpSection: View {
    var body: some View {
        Section {
            NavigationLink("Help") { HelpBrowserView() }
                .accessibilityIdentifier("helpLink")
        } footer: {
            Text("Short explanations of the app's modes and controls. They are part of the app and need no connection.")
        }
    }
}

struct HelpBrowserView: View {
    private let library: HelpLibrary? = HelpLibrary.bundled()
    @State private var query = ""

    var body: some View {
        content
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        if let library {
            HelpArticleList(library: library, entries: library.search(query))
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search help")
        } else {
            HelpMessage(text: "Help is not available.", identifier: "helpUnavailable")
        }
    }
}

private struct HelpArticleList: View {
    let library: HelpLibrary
    let entries: [HelpEntry]

    var body: some View {
        List {
            ForEach(entries) { (entry: HelpEntry) in
                NavigationLink(entry.title) { HelpArticleView(library: library, entry: entry) }
                    .accessibilityIdentifier("help.\(entry.id)")
            }
            if entries.isEmpty {
                Text("No help articles match")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("helpNoMatch")
            }
        }
        .accessibilityIdentifier("helpList")
    }
}

struct HelpArticleView: View {
    let library: HelpLibrary
    let entry: HelpEntry

    var body: some View {
        content
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        if let article = library.article(for: entry) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(article.blocks.enumerated()), id: \.offset) { (item: (offset: Int, element: HelpBlock)) in
                        HelpBlockView(block: item.element)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .accessibilityIdentifier("helpArticle.\(entry.id)")
        } else {
            HelpMessage(text: "This help article is missing.", identifier: "helpMissing")
        }
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(HelpMarkdown.inline(text))
                .font(Self.headingFont(level))
                .padding(.top, level == 1 ? 0 : 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("helpHeading")
        case let .paragraph(text):
            Text(HelpMarkdown.inline(text)).font(.body)
        case let .bullet(text):
            HelpListItem(marker: "•", text: text)
        case let .numbered(number, text):
            HelpListItem(marker: "\(number).", text: text)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .headline
        default: return .subheadline.bold()
        }
    }
}

private struct HelpListItem: View {
    let marker: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).font(.body).accessibilityHidden(true)
            Text(HelpMarkdown.inline(text)).font(.body)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HelpMessage: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(identifier)
    }
}
