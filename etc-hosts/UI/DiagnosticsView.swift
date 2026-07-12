// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import AppKit
import Darwin
import SwiftUI

// MARK: - Verify Helper diagnostics sheet

// A read-only checklist that confirms the privileged daemon is registered,
// reachable, version-matched, and trusts this app's signing key. Everything is
// gathered on appear (and via "Re-check"); nothing here mutates state.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [CheckRow] = []
    @State private var checking = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)
            content
        }
        .frame(width: 560, height: 540)
        .background(Theme.surface)
        .onAppear { recheck() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Verify Helper").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                Text("Confirm the privileged helper is installed, reachable, and trusts this app.")
                    .font(.system(size: 12)).foregroundColor(Theme.textDim)
            }
            Spacer()
            Button { recheck() } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SoftButton())
            .disabled(checking)
            Button("Close") { dismiss() }.buttonStyle(SoftButton())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    checkRowView(row)
                }
            }
            .padding(18)
        }
        .background(Theme.surface2)
    }

    private func checkRowView(_ row: CheckRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.status.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(row.status.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                Text(row.detail).font(.system(size: 12)).foregroundColor(Theme.textDim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    // MARK: Gathering

    private func recheck() {
        checking = true
        // Socket round-trips are blocking; run them off the main thread, then
        // publish results back on it.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = gather()
            DispatchQueue.main.async {
                rows = result
                checking = false
            }
        }
    }

    private func gather() -> [CheckRow] {
        var out: [CheckRow] = []

        // 1. Daemon registered & enabled.
        let enabled = ServiceManager.isEnabled
        out.append(CheckRow(
            title: "Helper registered & enabled",
            detail: "SMAppService status: \(ServiceManager.statusDescription()).",
            status: enabled ? .pass : .fail))

        // 2. Socket responding.
        let responding = HelperClient.isResponding()
        out.append(CheckRow(
            title: "Socket responding",
            detail: responding ? "The helper is answering on its local socket."
                               : "No response on the helper socket.",
            status: responding ? .pass : .fail))

        // 3 + 4 depend on the read-only status reply.
        let status = HelperClient.status()

        // 3. Version / protocol.
        if let s = status {
            let appProto = Helper.protocolVersion
            let match = s.protocolVersion == appProto
            out.append(CheckRow(
                title: "Helper version & protocol",
                detail: "Helper \(s.version), protocol v\(s.protocolVersion). App speaks protocol v\(appProto)."
                    + (match ? "" : " Mismatch — reinstall or update the helper."),
                status: match ? .pass : .warn))
        } else {
            out.append(CheckRow(
                title: "Helper version & protocol",
                detail: "Couldn't read the helper's status reply.",
                status: responding ? .warn : .fail))
        }

        // 4. Enrollment / trusted-key state.
        let needsEnroll = HelperClient.needsEnroll()
        if let s = status {
            var detail = s.enrolled ? "A trusted key is enrolled." : "No key enrolled yet."
            if let fp = s.pubkeyFingerprint { detail += " Fingerprint \(fp)." }
            if needsEnroll {
                detail += " This app's signing key is NOT the trusted key — re-run setup to enroll."
            } else {
                detail += " This app's signing key matches the trusted key."
            }
            let me = getuid()
            if let uid = s.authUID {
                let uidMatch = uid == me
                detail += " Authorized uid \(uid) (current uid \(me))."
                    + (uidMatch ? "" : " Different user — writes from this account are rejected.")
                let ok = s.enrolled && !needsEnroll && uidMatch
                out.append(CheckRow(title: "Trusted key & authorization",
                                    detail: detail,
                                    status: ok ? .pass : .warn))
            } else {
                detail += " No authorized uid recorded."
                out.append(CheckRow(title: "Trusted key & authorization",
                                    detail: detail,
                                    status: s.enrolled && !needsEnroll ? .warn : .fail))
            }
        } else {
            out.append(CheckRow(
                title: "Trusted key & authorization",
                detail: needsEnroll ? "This app's signing key is not enrolled with the helper."
                                    : "This app's signing key matches the enrolled key.",
                status: needsEnroll ? .warn : .pass))
        }

        // 5. Last accepted timestamp.
        if let s = status {
            let detail: String
            if s.lastTs > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(s.lastTs))
                detail = "Last accepted write: \(Self.dateFormatter.string(from: date))."
            } else {
                detail = "No writes accepted yet."
            }
            out.append(CheckRow(title: "Last accepted write", detail: detail, status: .info))
        }

        return out
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}

// MARK: - Row model

private struct CheckRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let status: CheckStatus
}

private enum CheckStatus {
    case pass, warn, fail, info

    var symbol: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pass: return Theme.green
        case .warn: return Theme.amber
        case .fail: return Theme.red
        case .info: return Theme.textDim
        }
    }
}
