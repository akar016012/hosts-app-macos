import AppKit
import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @StateObject private var store = HostsStore()
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var editorEntry: HostEntry? = nil
    @State private var showingEditor = false
    @State private var showingRaw = false
    @State private var showThemes = false

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
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.glow, .clear], center: .top, startRadius: 0, endRadius: 560)
                .ignoresSafeArea().allowsHitTesting(false)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, Theme.isLight ? .light : .dark)
        .onAppear { store.load(); store.unlockSession() }
        .sheet(isPresented: $showingEditor) {
            EntryEditor(entry: editorEntry) { ip, hosts, comment, enabled in
                if let e = editorEntry { store.update(e.id, ip: ip, hostnames: hosts, comment: comment, enabled: enabled) }
                else { store.add(ip: ip, hostnames: hosts, comment: comment, enabled: enabled) }
            }
        }
        .sheet(isPresented: $showingRaw) { RawEditor(text: store.rawText) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient.accentFill)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "number").font(.system(size: 23, weight: .bold)).foregroundColor(.white))
                .shadow(color: Theme.accent.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hosts").font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                Text(store.path).font(.system(size: 12.5, design: .monospaced)).foregroundColor(Theme.textDim)
            }
            Spacer(minLength: 16)

            Button { showThemes.toggle() } label: {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach([AppTheme.midnight, .carbon, .plum]) { Circle().fill($0.dot).frame(width: 9, height: 9) }
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
            }
            .buttonStyle(SoftButton())
            .popover(isPresented: $showThemes, arrowEdge: .bottom) { ThemeMenu() }

            LockPill(store: store)

            Button { store.flushDNS() } label: { Label("Flush DNS", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(SoftButton())
            Button { showingRaw = true } label: { Label("Raw", systemImage: "chevron.left.forwardslash.chevron.right") }
                .buttonStyle(SoftButton())
            Button { guarded { editorEntry = nil; showingEditor = true } } label: { Label("New", systemImage: "plus") }
                .buttonStyle(PrimaryButton())
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
        let fg: Color = toast.kind == .ok ? Color(hex: "04220f") : .white
        return Text(toast.msg)
            .font(.system(size: 13, weight: .semibold)).foregroundColor(fg)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
