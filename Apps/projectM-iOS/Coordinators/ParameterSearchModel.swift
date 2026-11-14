// ParameterSearchModel.swift — the parameter search's rows (UIX-009-R1, R5, R7; research UIX-009-D6, D7;
// specs/219-uix-009-parameter-search/contracts/parameter-search.md S4).
//
// * Matching and ranking are ParameterGraph's `ParameterSearch`, over every MOD-001 catalog descriptor: the
//   visual on screen is only shown on a row ("On screen"), never used to filter or order (UIX-009-R1).
// * A row's value is its UIX-003 inspector target's current value, or "Read only" without a Settings control.
// Every intermediate is a named, typed value (CI's type-check budget).
import ParameterGraph
import VisualParameters

struct ParameterSearchRow: Identifiable, Equatable {
    let id: ParameterID
    let name: String
    let group: String
    let value: String
    /// The parameter's group is drawn by the visual on screen (display only; research D6).
    let onScreen: Bool

    /// VoiceOver value: "<group>, <value>[, on screen]" (contract S4).
    var accessibilityValue: String {
        let base: String = group + ", " + value
        return onScreen ? base + ", on screen" : base
    }
}

/// One group of rows (the empty query's index).
struct ParameterSearchSection: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [ParameterSearchRow]
}

@MainActor
enum ParameterSearchRows {
    static let readOnly = "Read only"
    static let emptyTitle = "No parameters match"
    static let emptyHint = "Search a setting's name, its section (such as Glow) or its unit (such as %, s or Hz)."

    /// Every parameter the search covers: the whole MOD-001 visual catalog (UIX-009-R1).
    static var descriptors: [ParameterDescriptor] { ParameterInspectorCatalog.registry?.descriptors ?? [] }

    /// The IDs matching `query`, best first; independent of any visual or layer selection (UIX-009-R1).
    nonisolated static func ids(_ query: String, in descriptors: [ParameterDescriptor]) -> [ParameterID] {
        ParameterSearch.ids(query, in: descriptors)
    }

    /// The group drawn by `visual`, or nil (research D6). Glow is an effect over every visual, never a layer.
    nonisolated static func onScreenGroupID(for visual: VisualChoice?) -> String? {
        guard let visual else { return nil }
        switch visual {
        case .circularSpectrum, .camera, .photo, .video, .text: return VisualParameterCatalog.circularSpectrumGroup.id
        case .linearSpectrum: return VisualParameterCatalog.linearSpectrumGroup.id
        case .particleOrbit: return VisualParameterCatalog.particleOrbitGroup.id
        default: return nil
        }
    }

    /// Ranked rows for a non-empty query (one list), or every row for an empty one.
    static func rows(_ query: String, settings: AppSettings?, visual: VisualChoice?,
                     descriptors: [ParameterDescriptor] = descriptors) -> [ParameterSearchRow] {
        let byID: [ParameterID: ParameterDescriptor] = Dictionary(uniqueKeysWithValues: descriptors.map { (d: ParameterDescriptor) -> (ParameterID, ParameterDescriptor) in (d.id, d) })
        let groupID: String? = onScreenGroupID(for: visual)
        let matched: [ParameterID] = ids(query, in: descriptors)
        return matched.compactMap { (id: ParameterID) -> ParameterSearchRow? in
            guard let descriptor = byID[id] else { return nil }
            return row(descriptor, settings: settings, onScreenGroupID: groupID)
        }
    }

    /// The empty query's index: every row under its group, catalog order (UIX-009-R7).
    static func sections(settings: AppSettings?, visual: VisualChoice?,
                         descriptors: [ParameterDescriptor] = descriptors) -> [ParameterSearchSection] {
        let all: [ParameterSearchRow] = rows("", settings: settings, visual: visual, descriptors: descriptors)
        var sections: [ParameterSearchSection] = []
        for (descriptor, row) in zip(descriptors, all) {
            let groupID: String = descriptor.group.id
            if let last = sections.last, last.id == groupID {
                sections[sections.count - 1] = ParameterSearchSection(id: groupID, title: last.title, rows: last.rows + [row])
            } else {
                sections.append(ParameterSearchSection(id: groupID, title: descriptor.group.displayName, rows: [row]))
            }
        }
        return sections
    }

    static func row(_ descriptor: ParameterDescriptor, settings: AppSettings?, onScreenGroupID: String?) -> ParameterSearchRow {
        let value: String
        if let settings, let target = ParameterInspectorTargets.target(for: descriptor.id, settings: settings) {
            value = ParameterValueText.display(target.get(), descriptor: descriptor)
        } else {
            value = readOnly
        }
        let onScreen: Bool = onScreenGroupID == descriptor.group.id
        return ParameterSearchRow(id: descriptor.id, name: descriptor.displayName, group: descriptor.group.displayName,
                                  value: value, onScreen: onScreen)
    }
}
