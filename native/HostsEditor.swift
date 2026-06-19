import SwiftUI

// MARK: - App

@main
struct HostsEditorApp: App {
    var body: some Scene {
        WindowGroup("Hosts") {
            ContentView().frame(minWidth: 1080, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands { AppMenuCommands() }

        Settings { SettingsView() }
    }
}
