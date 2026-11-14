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

extension View {
    /// Segmented at standard text sizes, a menu at accessibility sizes (ACC-006-R1).
    func segmentedUnlessAccessibilitySize() -> some View {
        modifier(SegmentedUnlessAccessibilitySize())
    }
}
