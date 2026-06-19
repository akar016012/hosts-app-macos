import AppKit
import SwiftUI

// MARK: - Menu / command routing

// Menu commands live at the App scene level, away from the view that owns the
// sheet/search state. Rather than thread that state up, each command posts a
// lightweight notification that ContentView observes and acts on. This also
// lets the separate Settings window drive sheets on the main window.
extension Notification.Name {
    static let hpNewEntry   = Notification.Name("hosts.menu.newEntry")
    static let hpImport     = Notification.Name("hosts.menu.import")
    static let hpExport     = Notification.Name("hosts.menu.export")
    static let hpUndo       = Notification.Name("hosts.menu.undo")
    static let hpFind       = Notification.Name("hosts.menu.find")
    static let hpRaw        = Notification.Name("hosts.menu.raw")
    static let hpHistory    = Notification.Name("hosts.menu.history")
    static let hpFlushDNS   = Notification.Name("hosts.menu.flushDNS")
    static let hpManagePIN  = Notification.Name("hosts.menu.managePIN")
    static let hpEditTheme  = Notification.Name("hosts.menu.editTheme")
}

func postMenuCommand(_ name: Notification.Name) {
    NotificationCenter.default.post(name: name, object: nil)
}

private func showAboutPanel() {
    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        .applicationName: "Hosts",
        .applicationVersion: "1.0",
        .credits: NSAttributedString(
            string: "A native macOS editor for /etc/hosts.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]),
    ])
    NSApp.activate(ignoringOtherApps: true)
}

// MARK: - App menu bar

struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Hosts") { showAboutPanel() }
        }
        // Replace the default "New Window" item — this is a single-window app.
        CommandGroup(replacing: .newItem) {
            Button("New Entry…") { postMenuCommand(.hpNewEntry) }
                .keyboardShortcut("n")
            Divider()
            Button("Import Hosts File…") { postMenuCommand(.hpImport) }
                .keyboardShortcut("o")
            Button("Export Hosts File…") { postMenuCommand(.hpExport) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            // Option-Command-Z so it doesn't hijack text-field Undo (⌘Z) while
            // editing in a field or sheet.
            Button("Undo Last Change") { postMenuCommand(.hpUndo) }
                .keyboardShortcut("z", modifiers: [.command, .option])
        }
        CommandMenu("Hosts") {
            Button("Find") { postMenuCommand(.hpFind) }
                .keyboardShortcut("f")
            Divider()
            Button("Raw File") { postMenuCommand(.hpRaw) }
                .keyboardShortcut("r")
            Button("History") { postMenuCommand(.hpHistory) }
                .keyboardShortcut("y")
            Divider()
            Button("Flush DNS Cache") { postMenuCommand(.hpFlushDNS) }
                .keyboardShortcut("k")
        }
    }
}

// MARK: - Settings scene (⌘,)

struct SettingsView: View {
    @ObservedObject private var store = HostsStore.shared
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        TabView {
            Form {
                Picker("Unlock edits with", selection: $store.defaultUnlock) {
                    ForEach(UnlockMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                LabeledContent("App PIN") {
                    Button(store.pinSet ? "Change PIN…" : "Set PIN…") {
                        postMenuCommand(.hpManagePIN)
                    }
                }
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Picker("Theme", selection: $themeStore.theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                Button("Edit Custom Theme…") { postMenuCommand(.hpEditTheme) }
            }
            .padding(20)
            .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 460, height: 240)
    }
}
