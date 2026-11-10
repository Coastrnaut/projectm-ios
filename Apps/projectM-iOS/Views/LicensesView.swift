// LicensesView.swift — the Licenses screen (task T103; FR-067, ADR-0005). Lists every bundled
// third-party component, preset pack and asset with its license and attribution, from
// Resources/Licenses/licenses.json (written by scripts/collect_licenses.py), and the LGPL-2.1
// note on getting the engine source and replacing the library.
import SwiftUI

struct LicenseCatalog: Decodable {
    struct Component: Decodable, Identifiable {
        let id: String
        let name: String
        let group: String
        let license: String
        let attribution: String
        let version: String
        let file: String
    }

    struct Note: Decodable {
        let title: String
        let text: String
    }

    let components: [Component]
    let lgplNote: Note

    static func bundled(_ bundle: Bundle = .main) -> LicenseCatalog? {
        guard let url = bundle.url(forResource: "licenses", withExtension: "json", subdirectory: "Licenses"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LicenseCatalog.self, from: data)
    }

    static func text(of component: Component, bundle: Bundle = .main) -> String {
        let name = (component.file as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Licenses"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License text missing." }
        return text
    }

    /// Components grouped in manifest order.
    var groups: [(name: String, components: [Component])] {
        var order: [String] = []
        var byGroup: [String: [Component]] = [:]
        for component in components {
            if byGroup[component.group] == nil { order.append(component.group) }
            byGroup[component.group, default: []].append(component)
        }
        return order.map { ($0, byGroup[$0]!) }
    }
}

struct LicensesView: View {
    private let catalog = LicenseCatalog.bundled()

    var body: some View {
        List {
            if let catalog {
                Section {
                    NavigationLink(catalog.lgplNote.title) {
                        LicenseTextView(title: "LGPL-2.1", header: nil, text: catalog.lgplNote.text)
                    }
                    .accessibilityIdentifier("lgplNote")
                }
                ForEach(catalog.groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.components) { component in
                            NavigationLink {
                                LicenseTextView(title: component.name, header: header(component),
                                                text: LicenseCatalog.text(of: component))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.name)
                                    Text(component.license).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("license:\(component.id)")
                        }
                    }
                }
            } else {
                Text("The license list is missing from this build.")
            }
        }
        .navigationTitle("Licenses")
        .accessibilityIdentifier("licenses")
    }

    private func header(_ component: LicenseCatalog.Component) -> String {
        [component.license, component.attribution, component.version].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct LicenseTextView: View {
    let title: String
    let header: String?
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let header {
                    Text(header).font(.subheadline.bold())
                }
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("licenseText")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
