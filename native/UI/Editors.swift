import AppKit
import SwiftUI

// MARK: - Entry editor sheet

struct EntryEditor: View {
    let entry: HostEntry?
    let onSave: (String, [String], String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ip = ""
    @State private var hosts = ""
    @State private var comment = ""
    @State private var enabled = true
    @State private var error: String? = nil

    private var derivedGroup: HostGroup? {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard looksLikeIP(trimmed) else { return nil }
        let names = hosts.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return group(for: HostEntry(enabled: enabled, ip: trimmed, hostnames: names, comment: comment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry == nil ? "New entry" : "Edit entry")
                .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)

            field("IP ADDRESS", text: $ip, placeholder: "127.0.0.1", mono: true)
            field("HOSTNAMES (SPACE-SEPARATED)", text: $hosts, placeholder: "example.test www.example.test", mono: true)
            field("COMMENT (OPTIONAL)", text: $comment, placeholder: "Local dev override", mono: false)

            VStack(alignment: .leading, spacing: 6) {
                Text("GROUP (AUTO)").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
                HStack(spacing: 9) {
                    if let g = derivedGroup {
                        Text(g.letter).font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.accent).frame(width: 22, height: 22)
                            .background(Theme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(g.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        if looksLikeIP(ip.trimmingCharacters(in: .whitespaces)) {
                            IPBadge(ip: ip.trimmingCharacters(in: .whitespaces), enabled: true)
                        }
                    } else {
                        Text("Determined from the IP address").font(.system(size: 13)).foregroundColor(Theme.textDim)
                        Spacer()
                    }
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Toggle(isOn: $enabled) { Text("Enabled").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text) }
                .tint(Theme.green)
            if let error { Text(error).foregroundColor(Theme.red).font(.system(size: 13)) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 470).background(Theme.surface)
        .onAppear {
            if let e = entry {
                ip = e.ip; hosts = e.hostnames.joined(separator: " ")
                comment = e.comment; enabled = e.enabled
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: mono ? .monospaced : .default)).foregroundColor(Theme.text)
                .padding(.horizontal, 12).frame(height: 44).background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func save() {
        let trimmedIP = ip.trimmingCharacters(in: .whitespaces)
        let hostList = hosts.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if !looksLikeIP(trimmedIP) { error = "Enter a valid IPv4/IPv6 address."; return }
        if hostList.isEmpty { error = "Enter at least one hostname."; return }
        onSave(trimmedIP, hostList, comment.trimmingCharacters(in: .whitespaces), enabled)
        dismiss()
    }
}

// MARK: - Raw editor sheet

struct RawEditor: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Raw /etc/hosts").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                    Text("Read-only preview of the current file.")
                        .font(.system(size: 12)).foregroundColor(Theme.textDim)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(SoftButton(active: copied))
            }
            ScrollView {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).padding(12)
            }
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10)).frame(minHeight: 380)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(PrimaryButton())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 700, height: 540).background(Theme.surface)
    }
}
