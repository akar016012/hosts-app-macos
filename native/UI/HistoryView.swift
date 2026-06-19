import AppKit
import SwiftUI

// MARK: - Change history sheet

// Master/detail: a list of past versions on the left, the selected version's
// raw contents on the right, with a one-click revert.
struct HistorySheet: View {
    @ObservedObject var store: HostsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    private var selected: HostSnapshot? {
        store.history.first { $0.id == selectedID } ?? store.history.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)
            if store.history.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    versionList
                        .frame(width: 280)
                    Divider().background(Theme.border)
                    detail
                }
            }
        }
        .frame(width: 780, height: 560)
        .background(Theme.surface)
        .onAppear { selectedID = store.history.first?.id }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Change history").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                Text("Review past versions and revert to any of them.")
                    .font(.system(size: 12)).foregroundColor(Theme.textDim)
            }
            Spacer()
            Button("Close") { dismiss() }.buttonStyle(SoftButton())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundColor(Theme.textMut)
            Text("No history yet.").font(.system(size: 14)).foregroundColor(Theme.text2)
            Text("Versions are saved automatically as you make changes.")
                .font(.system(size: 12)).foregroundColor(Theme.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.history) { snap in
                    versionRow(snap)
                }
            }
            .padding(10)
        }
        .background(Theme.surface2)
    }

    private func versionRow(_ snap: HostSnapshot) -> some View {
        let isCurrent = snap.content == store.rawText
        let on = (selected?.id == snap.id)
        return Button { selectedID = snap.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snap.label).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text).lineLimit(1)
                    if isCurrent {
                        Text("CURRENT").font(.system(size: 9, weight: .bold)).tracking(0.5)
                            .foregroundColor(Theme.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.green.opacity(0.14)).clipShape(Capsule())
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text(HostsStore.shortTime(snap.timestamp))
                        .font(.system(size: 11)).foregroundColor(Theme.textDim)
                    Text("·").foregroundColor(Theme.textMut)
                    Text("\(snap.entryCount) entries").font(.system(size: 11)).foregroundColor(Theme.textDim)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.accentSoft : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Theme.accentBorder : Color.clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        if let snap = selected {
            let isCurrent = snap.content == store.rawText
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.label).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                        Text(HostsStore.shortTime(snap.timestamp))
                            .font(.system(size: 12)).foregroundColor(Theme.textDim)
                    }
                    Spacer()
                    Button { confirmRevert(snap) } label: {
                        Label("Revert to this version", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(isCurrent || !store.editingReady)
                    .help(store.editingReady ? "Write this version back to /etc/hosts"
                                             : "Unlock the session to revert")
                }
                ScrollView {
                    Text(snap.content.isEmpty ? "(empty)" : snap.content)
                        .font(.system(size: 12.5, design: .monospaced)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled).padding(12)
                }
                .background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    private func confirmRevert(_ snap: HostSnapshot) {
        let alert = NSAlert()
        alert.messageText = "Revert to this version?"
        alert.informativeText = "This rewrites /etc/hosts with the version from \(HostsStore.shortTime(snap.timestamp)). The current version is saved to history first, so you can undo it."
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.revert(to: snap)
            dismiss()
        }
    }
}
