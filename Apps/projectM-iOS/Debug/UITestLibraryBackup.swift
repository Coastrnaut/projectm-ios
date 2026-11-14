// UITestLibraryBackup.swift — DEBUG only: `-uitestStorageSheet` opens Settings › Storage as a sheet at
// launch, on whatever screen is showing, so LibraryBackupUITests (FILE-005-T16) reach the Backup
// section without starting audio or scrolling Settings (owner rule 7: a UI test under 30 s). Release
// builds return the view unchanged.
import SwiftUI

extension View {
    @ViewBuilder
    func uitestStorageSheet(_ coordinator: AppCoordinator) -> some View {
        #if DEBUG
        modifier(UITestStorageSheet(coordinator: coordinator))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct UITestStorageSheet: ViewModifier {
    let coordinator: AppCoordinator
    @State private var shown = ProcessInfo.processInfo.arguments.contains("-uitestStorageSheet")

    func body(content: Content) -> some View {
        content.sheet(isPresented: $shown) {
            NavigationStack {
                StorageUsageView(libraryBackup: coordinator.libraryBackup)
            }
        }
    }
}
#endif
