import SwiftUI

/// Opens the main window on the Dictation settings section (legacy Settings menu entry).
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        DashboardView(initialSection: .dictation)
            .environmentObject(appState)
    }
}
