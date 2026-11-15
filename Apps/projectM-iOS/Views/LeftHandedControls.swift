// LeftHandedControls.swift — ACC-010 (specs/248-acc-010-left-handed-layout, contract C2): Settings → Left-handed
// controls, and SHOW-014's emergency Black out button in the corner on the favoured side.
//
// The corner is placed with an explicit spacer, never a layout-direction flip or a mirrored view (research
// ACC-010-D1), so the button's symbol, label and B key are unchanged (ACC-010-R2, R5).
import PresentationLifecycle
import ShowControl
import SwiftUI

/// ACC-010-R1: the switch, on iPhone and iPad (Settings → Performance, before One-handed layout).
struct LeftHandedSection: View {
    @Bindable var setting: OneHandedSetting

    var body: some View {
        Section {
            Toggle(OneHandedSetting.leftHandedTitle, isOn: $setting.leftHanded)
                .accessibilityIdentifier("leftHandedToggle")
        } footer: {
            Text(OneHandedSetting.leftHandedFooter)
        }
    }
}

/// ACC-009 and ACC-010 in Settings → Performance: Left-handed controls (all devices), then One-handed layout (iPhone).
struct HandednessSections: View {
    let setting: OneHandedSetting

    var body: some View {
        LeftHandedSection(setting: setting).id("leftHanded")   // ACC-010-R1
        if setting.isPhone { OneHandedSection(setting: setting).id("oneHanded") }   // ACC-009-R1
    }
}

/// SHOW-014's button in the bottom corner on `side` (ACC-010-R2): trailing for right, leading for left.
struct EmergencyBlackoutCorner: View {
    let external: ExternalDisplayCoordinator
    let side: ControlsSide

    var body: some View {
        HStack {
            if side == .left {
                EmergencyBlackoutButton(external: external)
                Spacer()
            } else {
                Spacer()
                EmergencyBlackoutButton(external: external)
            }
        }
    }
}
