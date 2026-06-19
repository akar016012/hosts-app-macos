import AppKit
import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @ObservedObject private var store = HostsStore.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var onboarding = OnboardingStore.shared
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var editorEntry: HostEntry? = nil
    @State private var showingEditor = false
    @State private var showingRaw = false
    @State private var showingHistory = false
    @State private var showPinUnlock = false
    @State private var showPinSetup = false
    @State private var showUnlockChooser = false
    @State private var showProfile = false
    @State private var showProfileEdit = false
    @State private var showThemeEditor = false
    @State private var didRunInitialSetup = false
    @FocusState private var searchFocused: Bool

    private var visible: [HostEntry] {
        store.entries.filter { e in
            switch filter {
            case .all: break
            case .active: if !e.enabled { return false }
            case .disabled: if e.enabled { return false }
            }
            let q = search.trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty { return true }
            return e.ip.lowercased().contains(q)
                || e.hostnames.joined(separator: " ").lowercased().contains(q)
                || e.comment.lowercased().contains(q)
        }
    }

    var body: some View {
        let activeTheme = themeStore.theme
        let activePalette = activeTheme.palette

        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .background(Theme.headerBg)
                    .background(.ultraThinMaterial)
                Divider().background(Theme.border)
                toolbar
                stats
                Divider().background(Theme.border)
                list
            }
            if store.selectMode { BulkBar(store: store).padding(.bottom, 18) }
            if let toast = store.toast {
                toastView(toast).padding(.bottom, store.selectMode ? 88 : 24)
            }
            if !onboarding.completed {
                OnboardingView(store: store)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .id("\(activeTheme.rawValue)-\(themeStore.revision)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, activePalette.isLight ? .light : .dark)
        .tint(activePalette.accent)
        .accentColor(activePalette.accent)
        .onAppear {
            applyThemeAppearance(activeTheme)
            guard !didRunInitialSetup else { return }
            didRunInitialSetup = true
            store.load()
        }
        .onReceive(themeStore.$theme) { newTheme in
            applyThemeAppearance(newTheme)
        }
        // Auto-unlock only once onboarding is done — this fires with the current
        // value on appear (covering returning users) and again when the walkthrough
        // finishes, so the launch Touch ID prompt never appears behind the overlay.
        .onReceive(onboarding.$completed) { done in
            if done { store.autoUnlockIfPreferred() }
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditor(entry: editorEntry) { ip, hosts, comment, enabled in
                if let e = editorEntry { store.update(e.id, ip: ip, hostnames: hosts, comment: comment, enabled: enabled) }
                else { store.add(ip: ip, hostnames: hosts, comment: comment, enabled: enabled) }
            }
        }
        .sheet(isPresented: $showingRaw) { RawEditor(text: store.rawText) }
        .sheet(isPresented: $showingHistory) { HistorySheet(store: store) }
        .sheet(isPresented: $showPinUnlock) { PinUnlockSheet(store: store) }
        .sheet(isPresented: $showPinSetup) { PinSetupSheet(store: store) }
        .sheet(isPresented: $showProfileEdit) { ProfileEditSheet() }
        .sheet(isPresented: $showThemeEditor) { CustomThemeSheet() }
        .sheet(isPresented: $showUnlockChooser) {
            // The small delay lets the chooser finish dismissing before a second
            // sheet (PIN entry) is presented, avoiding a SwiftUI sheet conflict.
            UnlockChooserSheet(store: store,
                               onTouchID: { store.unlockSession() },
                               onPIN: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: presentPIN) })
        }
        .onReceive(NotificationCenter.default.publisher(for: .hpNewEntry)) { _ in
            guarded { editorEntry = nil; showingEditor = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hpImport)) { _ in importHosts() }
        .onReceive(NotificationCenter.default.publisher(for: .hpExport)) { _ in exportHosts() }
        .onReceive(NotificationCenter.default.publisher(for: .hpUndo)) { _ in store.undoLast() }
        .onReceive(NotificationCenter.default.publisher(for: .hpFind)) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .hpRaw)) { _ in showingRaw = true }
        .onReceive(NotificationCenter.default.publisher(for: .hpHistory)) { _ in showingHistory = true }
        .onReceive(NotificationCenter.default.publisher(for: .hpFlushDNS)) { _ in store.flushDNS() }
        .onReceive(NotificationCenter.default.publisher(for: .hpManagePIN)) { _ in showPinSetup = true }
        .onReceive(NotificationCenter.default.publisher(for: .hpEditTheme)) { _ in showThemeEditor = true }
        .onReceive(NotificationCenter.default.publisher(for: .hpUnregister)) { _ in store.unregisterHelper() }
    }

    // MARK: Import / export

    private func importHosts() {
        guard store.editingReady else { store.nudgeLocked(); return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a hosts file to import. This replaces the current /etc/hosts."
        if panel.runModal() == .OK, let url = panel.url {
            store.importHosts(from: url)
        }
    }

    private func exportHosts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hosts"
        panel.message = "Export the current /etc/hosts contents to a file."
        if panel.runModal() == .OK, let url = panel.url {
            store.exportHosts(to: url)
        }
    }

    // MARK: Unlock routing

    // Locked pill tapped: honor the saved default, otherwise ask.
    private func handleUnlockTap() {
        switch store.defaultUnlock {
        case .touchID: store.unlockSession()
        case .pin: presentPIN()
        case .ask: showUnlockChooser = true
        }
    }

    // Open PIN entry, or setup if no PIN exists yet.
    private func presentPIN() {
        if store.pinSet { showPinUnlock = true } else { showPinSetup = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient.accentFill)
                .frame(width: 48, height: 48)
                .overlay(HostsLogoMark())
            VStack(alignment: .leading, spacing: 2) {
                Text("Hosts").font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                Text(store.path).font(.system(size: 12.5, design: .monospaced)).foregroundColor(Theme.textDim)
            }
            Spacer(minLength: 16)

            LockPill(store: store, showPinUnlock: $showPinUnlock, showPinSetup: $showPinSetup, onUnlock: handleUnlockTap)

            Button { store.flushDNS() } label: { Label("Flush DNS", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(SoftButton())
            Button { showingHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                .buttonStyle(SoftButton())
            Button { showingRaw = true } label: { Label("Raw", systemImage: "chevron.left.forwardslash.chevron.right") }
                .buttonStyle(SoftButton())
            Button { guarded { editorEntry = nil; showingEditor = true } } label: { Label("New", systemImage: "plus") }
                .buttonStyle(PrimaryButton())

            ProfileBadge(showProfile: $showProfile, store: store,
                         showProfileEdit: $showProfileEdit, showPinSetup: $showPinSetup,
                         showThemeEditor: $showThemeEditor)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    // MARK: Toolbar + stats

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.textDim)
                TextField("Search IP, hostname, or comment…", text: $search)
                    .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.text)
                    .focused($searchFocused)
                    .onExitCommand { if !search.isEmpty { search = "" } else { searchFocused = false } }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    }
                    .buttonStyle(.plain).foregroundColor(Theme.textDim)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            SegmentedFilter(filter: $filter, store: store)

            Button {
                if store.selectMode { store.exitSelect() } else { store.enterSelect() }
            } label: {
                Label(store.selectMode ? "Cancel" : "Select",
                      systemImage: store.selectMode ? "xmark" : "checklist")
            }
            .buttonStyle(SoftButton(active: store.selectMode))
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)
    }

    private var stats: some View {
        HStack(spacing: 7) {
            Text("\(store.activeCount) active").foregroundColor(Theme.green)
            Text("·").foregroundColor(Theme.textMut)
            Text("\(store.entries.count) total").foregroundColor(Theme.text2)
            if store.blockedCount > 0 {
                Text("·").foregroundColor(Theme.textMut)
                Text("\(store.blockedCount) blocked").foregroundColor(Theme.red)
            }
            if store.duplicateCount > 0 {
                Text("·").foregroundColor(Theme.textMut)
                Label("\(store.duplicateCount) duplicate \(store.duplicateCount == 1 ? "host" : "hosts")",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.amber)
                    .help("A hostname maps to more than one IP across enabled entries. The first match wins.")
            }
            Spacer()
        }
        .font(.system(size: 12.5, weight: .semibold))
        .padding(.horizontal, 22).padding(.bottom, 12)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: []) {
                ForEach(store.grouped(visible), id: \.group.id) { pair in
                    GroupSection(store: store, group: pair.group, entries: pair.entries,
                                 onEdit: { e in guarded { editorEntry = e; showingEditor = true } },
                                 onDelete: { e in guarded { confirmDelete(e) } })
                }
                if visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 34)).foregroundColor(Theme.textMut)
                        Text("No matching entries.").font(.system(size: 14)).foregroundColor(Theme.text2)
                    }.frame(maxWidth: .infinity).padding(.top, 70)
                }
            }
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 40)
            .animation(.easeInOut(duration: 0.2), value: visible)
        }
    }

    // MARK: Helpers

    private func guarded(_ action: () -> Void) {
        if store.editingReady { action() } else { store.nudgeLocked() }
    }

    private func confirmDelete(_ entry: HostEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete entry?"
        alert.informativeText = entry.hostnames.joined(separator: " ")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { store.delete(entry.id) }
    }

    private func toastView(_ toast: (msg: String, kind: HostsStore.ToastKind)) -> some View {
        let bg: Color = toast.kind == .ok ? Theme.green : toast.kind == .error ? Theme.red : Theme.surface2
        // Pick legible text per background instead of a hardcoded color, so light
        // themes (where the info background is a pale surface) stay readable.
        let fg: Color = toast.kind == .info ? Theme.text : Theme.readable(on: bg)
        return Text(toast.msg)
            .font(.system(size: 13, weight: .semibold)).foregroundColor(fg)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func applyThemeAppearance(_ theme: AppTheme) {
        let name: NSAppearance.Name = theme.palette.isLight ? .aqua : .darkAqua
        NSApp.appearance = NSAppearance(named: name)
    }
}
