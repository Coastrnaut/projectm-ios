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
        content.sheet(isPresented: $shown) { storage }
    }

    /// Split out so the type checker stays well under CI's limit (150 ms was reached).
    private var storage: some View {
        let backup: LibraryBackupCoordinator = coordinator.libraryBackup
        return NavigationStack { StorageUsageView(libraryBackup: backup) }
    }
}
#endif
