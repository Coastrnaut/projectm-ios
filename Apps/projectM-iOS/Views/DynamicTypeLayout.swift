// DynamicTypeLayout.swift — ACC-006 helpers for accessibility text sizes (specs/087-acc-006-dynamic-type-inspector).
//
// `segmentedUnlessAccessibilitySize()`: a segmented picker at standard sizes; a menu picker (its title and
// the chosen value in one row that wraps) at accessibility sizes. UISegmentedControl keeps its segments in
// one row, so at AX5 the audit found their titles clipped and not scaled (Settings › Linear Spectrum,
// 2026-11-13). Standard sizes are unchanged, so the suites that read `segmentedControls[...]` still do.
import SwiftUI

struct SegmentedUnlessAccessibilitySize: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.menu)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

/// An icon and a title side by side, the title wrapping in its own column (ACC-006-R1). A `Label` in a
/// list row (a NavigationLink's or a Button's label) wraps its title under the icon at AX3 and AX5, and the
/// audit reports that as clipped text and partly unsupported Dynamic Type (Show › Scene Folders,
/// 2026-11-14). The icon is decorative; the row reads its title.
struct IconTitleRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage).accessibilityHidden(true)
            // The title takes the row's whole width: without the spacer a NavigationLink's row offered it
            // about half the width at AX3, so "Scene Folders" wrapped beside free space and the audit
            // reported its Dynamic Type as partly unsupported.
            Text(title).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Spacer(minLength: 0)
        }
    }
}

extension View {
    /// Segmented at standard text sizes, a menu at accessibility sizes (ACC-006-R1).
    func segmentedUnlessAccessibilitySize() -> some View {
        modifier(SegmentedUnlessAccessibilitySize())
    }
}
