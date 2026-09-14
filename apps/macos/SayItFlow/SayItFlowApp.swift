import SwiftUI

@main
struct SayItFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarIconLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 860, minHeight: 600)
        }
    }
}

private struct MenuBarIconLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(nsImage: MenuBarIconRenderer.icon(for: appState))
            .frame(width: 18, height: 18)
            .accessibilityLabel("SayItFlow")
    }
}

