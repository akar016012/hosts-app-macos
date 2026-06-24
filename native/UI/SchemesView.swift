// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Schemes manager

// Master/detail sheet (mirrors HistorySheet): saved schemes on the left, the
// selected scheme's details + a diff-previewed Apply on the right. Schemes let the
// user switch whole /etc/hosts environments (local / staging / QA / blocking).
struct SchemesSheet: View {
    @ObservedObject var store: HostsStore
    @ObservedObject private var schemes = SchemeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var editing: Scheme?          // non-nil → editor sheet open
    @State private var creatingNew = false
    @State private var applying: Scheme?          // non-nil → apply/diff sheet open

    private var selected: Scheme? {
        schemes.schemes.first { $0.id == selectedID } ?? schemes.schemes.first
    }
    private var activeID: UUID? { schemes.activeScheme(matching: store.rawText)?.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)
            if schemes.schemes.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    schemeList.frame(width: 280)
                    Divider().background(Theme.border)
                    detail
                }
            }
        }
        .frame(width: 820, height: 580)
        .background(Theme.surface)
        .onAppear { if selectedID == nil { selectedID = schemes.schemes.first?.id } }
        .sheet(item: $editing) { scheme in
            SchemeEditorSheet(store: store, original: scheme) { selectedID = $0.id }
        }
        .sheet(isPresented: $creatingNew) {
            SchemeEditorSheet(store: store, original: nil) { selectedID = $0.id }
        }
        .sheet(item: $applying) { scheme in
            ApplySchemeSheet(store: store, scheme: scheme) { dismiss() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Schemes").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                Text("Switch whole /etc/hosts environments in one click.")
                    .font(.system(size: 12)).foregroundColor(Theme.textDim)
            }
            Spacer()
            Button { store.captureCurrentAsScheme(name: "Current hosts"); selectFirst() } label: {
                Label("Save current", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SoftButton())
            .help("Capture the current /etc/hosts as a new scheme")
            Button { importBundle() } label: { Label("Import", systemImage: "tray.and.arrow.down") }
                .buttonStyle(SoftButton())
            Button { creatingNew = true } label: { Label("New", systemImage: "plus") }
                .buttonStyle(PrimaryButton())
            Button("Close") { dismiss() }.buttonStyle(SoftButton())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.3.group").font(.system(size: 36)).foregroundColor(Theme.textMut)
            Text("No schemes yet.").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
            Text("Save the current hosts file as a scheme, or create one from scratch —\nthen switch between Local dev, Staging, QA, or a Blocklist in one click.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12.5)).foregroundColor(Theme.textDim)
            HStack(spacing: 10) {
                Button { store.captureCurrentAsScheme(name: "Current hosts"); selectFirst() } label: {
                    Label("Save current as scheme", systemImage: "square.and.arrow.down")
                }.buttonStyle(SoftButton())
                Button { creatingNew = true } label: { Label("New scheme", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private var schemeList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(schemes.schemes) { scheme in
                    schemeRow(scheme)
                }
            }
            .padding(10)
        }
        .background(Theme.surface2)
    }

    private func schemeRow(_ scheme: Scheme) -> some View {
        let on = (selected?.id == scheme.id)
        let isActive = (scheme.id == activeID)
        return Button { selectedID = scheme.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scheme.name).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text).lineLimit(1)
                    if isActive {
                        Text("ACTIVE").font(.system(size: 9, weight: .bold)).tracking(0.5)
                            .foregroundColor(Theme.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.green.opacity(0.14)).clipShape(Capsule())
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text("\(scheme.entryCount) entries").font(.system(size: 11)).foregroundColor(Theme.textDim)
                    if let applied = scheme.lastAppliedAt {
                        Text("·").foregroundColor(Theme.textMut)
                        Text("used \(HostsStore.shortTime(applied))").font(.system(size: 11)).foregroundColor(Theme.textDim)
                    }
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
        if let scheme = selected {
            let isActive = (scheme.id == activeID)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scheme.name).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                        Text("\(scheme.entryCount) entries · created \(HostsStore.shortTime(scheme.createdAt))")
                            .font(.system(size: 12)).foregroundColor(Theme.textDim)
                    }
                    Spacer()
                    Button { applying = scheme } label: {
                        Label(isActive ? "Active" : "Apply…", systemImage: isActive ? "checkmark" : "arrow.right.circle")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(isActive || !store.editingReady)
                    .help(store.editingReady ? "Preview the changes, then write this scheme to /etc/hosts"
                                             : "Unlock the session to apply")
                }
                if !scheme.note.isEmpty {
                    Text(scheme.note).font(.system(size: 12.5)).foregroundColor(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !scheme.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(scheme.tags, id: \.self) { tag in
                            Text(tag).font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Theme.text2)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.surface2).clipShape(Capsule())
                        }
                    }
                }
                ScrollView {
                    Text(scheme.content.isEmpty ? "(empty)" : scheme.content)
                        .font(.system(size: 12.5, design: .monospaced)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled).padding(12)
                }
                .background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 10) {
                    Button { editing = scheme } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(SoftButton())
                    Button { duplicate(scheme) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        .buttonStyle(SoftButton())
                    Button { exportScheme(scheme) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SoftButton())
                    Spacer()
                    Button { confirmDelete(scheme) } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(SoftButton())
                        .foregroundColor(Theme.red)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    // MARK: Actions

    private func selectFirst() { selectedID = schemes.schemes.first?.id }

    private func duplicate(_ scheme: Scheme) {
        if let copy = schemes.duplicate(scheme.id) { selectedID = copy.id }
    }

    private func confirmDelete(_ scheme: Scheme) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(scheme.name)”?"
        alert.informativeText = "This removes the scheme. Your current /etc/hosts is not changed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            schemes.delete(scheme.id)
            selectedID = schemes.schemes.first?.id
        }
    }

    private func exportScheme(_ scheme: Scheme) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(scheme.name).\(SchemeStore.bundleExtension)"
        panel.message = "Export this scheme to share it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try schemes.exportBundle([scheme.id], to: url); store.notify("Exported “\(scheme.name)”", .ok) }
        catch { store.notify("Couldn't export the scheme. Try a different location.", .error) }
    }

    private func importBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // .hostsscheme is a JSON payload with a custom extension; accept both it and
        // plain .json so bundles round-trip regardless of how they were saved/renamed.
        let schemeType = UTType(filenameExtension: SchemeStore.bundleExtension) ?? .json
        panel.allowedContentTypes = [schemeType, .json]
        panel.message = "Import a scheme bundle (.\(SchemeStore.bundleExtension) or .json)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try schemes.importBundle(from: url)
            store.notify("Imported \(n) scheme\(n == 1 ? "" : "s")", .ok)
            selectedID = schemes.schemes.first?.id
        } catch {
            store.notify("Couldn't import that file. Make sure it's a valid scheme export (.\(SchemeStore.bundleExtension) or .json).", .error)
        }
    }
}

// MARK: - Scheme editor

// Create or edit a scheme: name, optional note + tags, and the hosts body. The body
// can be seeded from the current file when creating from scratch.
struct SchemeEditorSheet: View {
    @ObservedObject var store: HostsStore
    let original: Scheme?
    let onSave: (Scheme) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var note: String
    @State private var tagsText: String
    @State private var content: String

    init(store: HostsStore, original: Scheme?, onSave: @escaping (Scheme) -> Void) {
        self.store = store; self.original = original; self.onSave = onSave
        _name = State(initialValue: original?.name ?? "")
        _note = State(initialValue: original?.note ?? "")
        _tagsText = State(initialValue: (original?.tags ?? []).joined(separator: ", "))
        // New schemes seed from the current file so "tweak then save" is one step.
        _content = State(initialValue: original?.content ?? store.rawText)
    }

    private var parsedTags: [String] {
        tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(original == nil ? "New scheme" : "Edit scheme")
                    .font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider().background(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name") {
                        TextField("e.g. Client A staging", text: $name)
                            .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.text)
                    }
                    field("Note (optional)") {
                        TextField("What this scheme is for", text: $note)
                            .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.text)
                    }
                    field("Tags (optional, comma-separated)") {
                        TextField("staging, client-a", text: $tagsText)
                            .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(Theme.text)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hosts contents").font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.textDim)
                        TextEditor(text: $content)
                            .font(.system(size: 12.5, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 240)
                            .padding(8)
                            .background(Theme.surface2)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 560)
        .background(Theme.surface)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.textDim)
            content()
                .padding(.horizontal, 12).frame(height: 40)
                .background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let s = SchemeStore.shared
        if let original {
            var updated = original
            updated.name = trimmed; updated.note = note; updated.tags = parsedTags; updated.content = content
            s.update(updated)
            onSave(updated)
        } else {
            let created = Scheme(name: s.uniqueName(from: trimmed), note: note, tags: parsedTags, content: content)
            s.add(created)
            onSave(created)
        }
        dismiss()
    }
}

// MARK: - Apply confirm (diff preview)

// Shows exactly what applying the scheme will change, with an optional DNS flush,
// before the privileged write. The current version is snapshotted first, so apply
// is always reversible via History / Undo.
struct ApplySchemeSheet: View {
    @ObservedObject var store: HostsStore
    let scheme: Scheme
    let onApplied: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("hosts.scheme.flushAfterApply") private var flushAfter = false

    private var segments: [DiffSegment] { HostsDiff.diff(store.rawText, scheme.content) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apply “\(scheme.name)”").font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text)
                    Text("Review the changes before writing to /etc/hosts.")
                        .font(.system(size: 12)).foregroundColor(Theme.textDim)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton()).keyboardShortcut(.cancelAction)
                Button { apply() } label: { Label("Apply", systemImage: "arrow.right.circle") }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(HostsDiff.stat(segments).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider().background(Theme.border)

            DiffView(segments: segments).padding(16)

            Divider().background(Theme.border)
            HStack {
                Toggle(isOn: $flushAfter) {
                    Text("Flush DNS cache after applying").font(.system(size: 12.5)).foregroundColor(Theme.text2)
                }
                .toggleStyle(.checkbox)
                Spacer()
                Text("Current version is saved to History first.")
                    .font(.system(size: 11.5)).foregroundColor(Theme.textMut)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 760, height: 580)
        .background(Theme.surface)
    }

    private func apply() {
        store.applyScheme(id: scheme.id, name: scheme.name, content: scheme.content, flushAfter: flushAfter)
        onApplied()
        dismiss()
    }
}
