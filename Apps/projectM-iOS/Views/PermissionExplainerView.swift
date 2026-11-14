// PermissionExplainerView.swift — the sheet shown right before iOS's camera or local network prompt
// (UIX-015-R3, R5, R12; contracts/permission-explainer.md C1). The same pattern as FR-005's microphone
// sheet: a decorative symbol, the catalog's name, its usage text (the Info.plist text), what happens if
// the user declines, then Continue and Not now. It scrolls; at accessibility text sizes the buttons
// stack. No animation of its own and no announcement (VoiceOver reads the sheet when it appears).
import SwiftUI

struct PermissionExplainerView: View {
    let permission: AppPermission
    let onContinue: () -> Void
    let onNotNow: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                texts
                buttons
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("permissionExplainer.\(permission.rawValue)")
    }

    private var header: some View {
        let entry: PermissionEntry = PermissionCatalog.entry(permission)
        return VStack(spacing: 12) {
            Image(systemName: PermissionCatalog.explainerSymbol(permission))
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(entry.name)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("permissionExplainerTitle")
        }
    }

    @ViewBuilder private var texts: some View {
        let usage: String = PermissionCatalog.entry(permission).usageDescription
        Text(usage)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("permissionExplainerText")
        if let fallback = PermissionCatalog.explainerFallback(permission) {
            Text(fallback)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permissionExplainerFallback")
        }
        Text(PermissionCatalog.explainerNote)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var buttons: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { continueButton; notNowButton }
        } else {
            HStack(spacing: 12) { notNowButton; continueButton }
        }
    }

    private var continueButton: some View {
        Button("Continue", action: onContinue)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("permissionExplainerContinue")
    }

    private var notNowButton: some View {
        Button("Not now", action: onNotNow)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("permissionExplainerNotNow")
    }
}

extension View {
    /// UIX-015: presents the coordinator's pending explainer; a swipe down counts as Not now.
    func permissionExplainerSheet(_ explainers: PermissionExplainerCoordinator?) -> some View {
        let presented = Binding<Bool>(
            get: { () -> Bool in explainers?.pending != nil },
            set: { (shown: Bool) -> Void in if !shown { explainers?.notNow() } })
        return sheet(isPresented: presented) {
            if let explainers, let permission = explainers.pending {
                PermissionExplainerView(permission: permission,
                                        onContinue: { explainers.continuePending() },
                                        onNotNow: { explainers.notNow() })
            }
        }
    }
}
