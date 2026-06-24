// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import AppKit
import SwiftUI

// MARK: - App

@main
struct HostsEditorApp: App {
    // Force the Sparkle updater to start at launch so its scheduled background
    // checks begin regardless of whether the menu is ever opened.
    init() { _ = UpdaterManager.shared }

    var body: some Scene {
        WindowGroup("Hosts") {
            ContentView().frame(minWidth: 1240, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .commands { AppMenuCommands() }

        Settings { SettingsView() }

        // Menu-bar quick switch: apply any saved scheme to /etc/hosts in one click
        // without bringing the main window forward.
        MenuBarExtra("Hosts", systemImage: "rectangle.3.group") {
            SchemesMenuBar()
        }
    }
}

// MARK: - Menu bar content

// Lists saved schemes for one-click switching. Clicking applies the scheme directly
// (the quick-switch flow); History/Undo remain the safety net. Picking a scheme
// while locked surfaces an unlock nudge in the main window instead of failing
// silently.
struct SchemesMenuBar: View {
    @ObservedObject private var store = HostsStore.shared
    @ObservedObject private var schemes = SchemeStore.shared

    private var activeID: UUID? { schemes.activeScheme(matching: store.rawText)?.id }

    var body: some View {
        if schemes.schemes.isEmpty {
            Text("No schemes yet")
            Button("Create a Scheme…") { openManager() }
        } else {
            ForEach(schemes.schemes) { scheme in
                Button {
                    apply(scheme)
                } label: {
                    // A checkmark marks the currently-active scheme.
                    if scheme.id == activeID { Label(scheme.name, systemImage: "checkmark") }
                    else { Text(scheme.name) }
                }
                .disabled(scheme.id == activeID)
            }
            Divider()
            Button("Manage Schemes…") { openManager() }
        }
        Divider()
        Button("Open Hosts") { bringWindowForward() }
        Button("Quit Hosts") { NSApplication.shared.terminate(nil) }
    }

    private func apply(_ scheme: Scheme) {
        bringWindowForward()
        guard store.editingReady else {
            store.notify("Unlock Hosts to apply “\(scheme.name)”", .error)
            return
        }
        store.applyScheme(id: scheme.id, name: scheme.name, content: scheme.content, flushAfter: false)
    }

    private func openManager() {
        bringWindowForward()
        postMenuCommand(.hpSchemes)
    }

    private func bringWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
