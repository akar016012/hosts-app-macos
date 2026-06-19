import SwiftUI

// MARK: - App

@main
struct HostsEditorApp: App {
    var body: some Scene {
        WindowGroup("Hosts") {
            ContentView().frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}
