// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import AppKit
import SwiftUI

// MARK: - Shared components

struct IPBadge: View {
    let ip: String
    let enabled: Bool
    var body: some View {
        let k = ipKind(ip)
        let fg = Theme.isLight ? k.lightText : k.base
        Text(ip)
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            .foregroundColor(fg)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(k.base.opacity(Theme.isLight ? 0.10 : 0.15))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(k.base.opacity(0.30), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(enabled ? 1 : 0.85)
            .accessibilityElement()
            .accessibilityLabel("IP address \(ip)")
    }
}

struct SourceChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold)).tracking(0.5)
            .foregroundColor(Theme.text2)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement()
            .accessibilityLabel("Source: \(text)")
    }
}

struct StatusDot: View {
    let status: HostStatus
    private var color: Color { status == .online ? Theme.green : status == .offline ? Theme.red : Theme.textMut }
    private var label: String { status == .online ? "online" : status == .offline ? "offline" : "—" }
    private var a11yLabel: String { status == .online ? "Reachable" : status == .offline ? "Unreachable" : "Reachability unknown" }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(status == .na ? Theme.textMut : Theme.text2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }
}

// Green when on, amber when a group is partially on, grey when off.
struct ThemedToggle: View {
    let on: Bool
    var amber: Bool = false
    var enabled: Bool = true
    var accessibilityText: String = ""
    let action: () -> Void
    @State private var splashScale = 0.65
    @State private var splashOpacity = 0.0
    @State private var knobPop = false

    var body: some View {
        Button {
            if enabled { runSplash() }
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(splashColor.opacity(0.24))
                    .frame(width: 40, height: 40)
                    .scaleEffect(splashScale)
                    .opacity(splashOpacity)

                Capsule()
                    .fill(on || amber ? AnyShapeStyle(amber ? LinearGradient.toggleAmber : LinearGradient.accentFill)
                                      : AnyShapeStyle(Theme.toggleOff))
                    .frame(width: 46, height: 27)
                    .overlay(
                        Capsule()
                            .stroke(splashColor.opacity(0.45), lineWidth: 1.5)
                            .scaleEffect(x: splashScale, y: splashScale * 1.12)
                            .opacity(splashOpacity)
                    )
                    .overlay(alignment: on || amber ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 21, height: 21)
                            .scaleEffect(knobPop ? 1.12 : 1)
                            .padding(3)
                    }
            }
            .frame(width: 56, height: 45)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.16), value: on)
        .animation(.easeOut(duration: 0.16), value: amber)
        .animation(.easeOut(duration: 0.16), value: enabled)
        .accessibilityLabel(accessibilityText.isEmpty ? "Toggle" : accessibilityText)
        .accessibilityValue(on ? "On" : (amber ? "Partially on" : "Off"))
    }

    private var splashColor: Color {
        amber ? Theme.amber : Theme.accent
    }

    private func runSplash() {
        splashScale = 0.65
        splashOpacity = 0.8

        withAnimation(.spring(response: 0.18, dampingFraction: 0.58)) {
            knobPop = true
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.34)) {
                splashScale = 1.8
                splashOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                knobPop = false
            }
        }
    }
}

// MARK: - Group section

struct GroupSection: View {
    @ObservedObject var store: HostsStore
    let group: HostGroup
    let entries: [HostEntry]
    let onEdit: (HostEntry) -> Void
    let onDelete: (HostEntry) -> Void

    private var collapsed: Bool { store.collapsed.contains(group.rawValue) }
    private var onCount: Int { entries.filter(\.enabled).count }
    private var allOn: Bool { onCount == entries.count }
    private var anyOn: Bool { onCount > 0 }

    var body: some View {
        VStack(spacing: 8) {
            header
            if !collapsed {
                ForEach(entries) { e in
                    EntryRow(store: store, entry: e, onEdit: { onEdit(e) }, onDelete: { onDelete(e) })
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: collapsed)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button { withAnimation { store.toggleCollapse(group) } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(Theme.textDim)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .frame(width: 20, height: 20)
            }.buttonStyle(.plain)

            Text(group.letter)
                .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(group.name).font(.system(size: 14.5, weight: .bold)).foregroundColor(Theme.text)
            Text("\(onCount)/\(entries.count) on")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.text2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Theme.surface2).clipShape(Capsule())
            Text(group.source).font(.system(size: 12)).foregroundColor(Theme.textDim)
            Spacer()
            ThemedToggle(on: allOn, amber: anyOn && !allOn, enabled: store.editingReady, accessibilityText: "Toggle group \(group.name)") {
                store.toggleGroup(entries, on: !anyOn)
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Entry row

struct EntryRow: View {
    @ObservedObject var store: HostsStore
    let entry: HostEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    private var selected: Bool { store.selection.contains(entry.id) }

    var body: some View {
        HStack(spacing: 13) {
            if store.selectMode {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19)).foregroundColor(selected ? Theme.accent : Theme.textMut)
                    .frame(width: 28)
            } else {
                ThemedToggle(on: entry.enabled, enabled: store.editingReady, accessibilityText: "Toggle \(entry.hostnames.first ?? entry.ip)") { store.toggle(entry.id) }
            }

            IPBadge(ip: entry.ip, enabled: entry.enabled).frame(minWidth: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(entry.hostnames.first ?? "")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
                    if entry.hostnames.count > 1 {
                        Text(entry.hostnames.dropFirst().joined(separator: " "))
                            .font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.textDim)
                    }
                }
                if !entry.comment.isEmpty {
                    Text("# \(entry.comment)").font(.system(size: 12)).foregroundColor(Theme.textDim).lineLimit(1)
                }
            }
            Spacer(minLength: 10)

            if !store.selectMode {
                SourceChip(text: sourceTag(for: entry))
                StatusDot(status: store.status(for: entry)).frame(width: 64, alignment: .leading)
                Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(IconButton())
                    .opacity(store.editingReady ? 1 : 0.4)
                    .accessibilityLabel("Edit \(entry.hostnames.first ?? entry.ip)")
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(IconButton(danger: true))
                    .opacity(store.editingReady ? 1 : 0.4)
                    .accessibilityLabel("Delete \(entry.hostnames.first ?? entry.ip)")
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 64)
        .background(rowBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.enabled ? AnyShapeStyle(LinearGradient.accentFill) : AnyShapeStyle(Theme.textMut))
                .frame(width: 3, height: 34)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(entry.enabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { if store.selectMode { store.toggleSelect(entry.id) } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var rowBackground: Color {
        if selected { return Theme.accentSoft }
        return hovering ? Theme.surface : (entry.enabled ? Theme.row : Theme.rowOff)
    }
    private var borderColor: Color {
        if selected { return Theme.accentBorder }
        return hovering ? Theme.accentBorder : Theme.rowBorder
    }
}

// MARK: - Bulk action bar

struct BulkBar: View {
    @ObservedObject var store: HostsStore
    var body: some View {
        HStack(spacing: 10) {
            Text("\(store.selection.count) selected")
                .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                .padding(.trailing, 4)
            Button { store.setEnabled(store.selection, enabled: true) } label: { Label("Enable", systemImage: "checkmark.circle") }
                .buttonStyle(SoftButton())
            Button { store.setEnabled(store.selection, enabled: false) } label: { Label("Disable", systemImage: "minus.circle") }
                .buttonStyle(SoftButton())
            Button { confirmBulkDelete() } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(SoftButton(danger: true))
            Divider().frame(height: 22).overlay(Theme.border)
            Button { store.exitSelect() } label: { Text("Done") }.buttonStyle(PrimaryButton())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface.opacity(0.8))
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border.opacity(0.6), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.15), value: store.selection.isEmpty)
    }

    private func confirmBulkDelete() {
        let n = store.selection.count
        guard n > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(n) \(n == 1 ? "entry" : "entries")?"
        alert.informativeText = "This removes the selected \(n == 1 ? "entry" : "entries") from /etc/hosts."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { store.deleteMany(store.selection) }
    }
}
