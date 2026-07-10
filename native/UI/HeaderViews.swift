// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import SwiftUI

// MARK: - In-app logo mark (mirrors the AppIcon.svg topology)

struct HostsLogoMark: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            // All radii scale with canvas width so the mark looks right at any size.
            let R:  CGFloat = size.width * 0.354   // satellite orbit  (~17 pt at 48 pt)
            let cR: CGFloat = size.width * 0.146   // central circle   (~ 7 pt)
            let sR: CGFloat = size.width * 0.083   // satellite circle  (~ 4 pt)
            let lW: CGFloat = max(1, size.width * 0.031) // line width (~1.5 pt)

            // Equilateral-triangle satellite positions — same geometry as AppIcon.svg
            let sats: [CGPoint] = [
                CGPoint(x: cx,           y: cy - R),
                CGPoint(x: cx - R*0.866, y: cy + R*0.5),
                CGPoint(x: cx + R*0.866, y: cy + R*0.5),
            ]

            // Connection lines: central circle edge → satellite circle edge
            for sat in sats {
                let dx = sat.x - cx, dy = sat.y - cy
                let len = hypot(dx, dy)
                let ux = dx/len, uy = dy/len
                var p = Path()
                p.move(to: CGPoint(x: cx + ux*cR,       y: cy + uy*cR))
                p.addLine(to: CGPoint(x: sat.x - ux*sR, y: sat.y - uy*sR))
                ctx.stroke(p, with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: lW, lineCap: .round))
            }

            // Satellite nodes: outer ring + inner dot
            for sat in sats {
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: sat.x-sR, y: sat.y-sR, width: sR*2, height: sR*2)),
                    with: .color(.white.opacity(0.55)),
                    style: StrokeStyle(lineWidth: lW)
                )
                let dR = sR * 0.45
                ctx.fill(
                    Path(ellipseIn: CGRect(x: sat.x-dR, y: sat.y-dR, width: dR*2, height: dR*2)),
                    with: .color(.white.opacity(0.9))
                )
            }

            // Central hub — solid filled circle
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx-cR, y: cy-cR, width: cR*2, height: cR*2)),
                with: .color(.white.opacity(0.95))
            )
        }
    }
}

// MARK: - Header components

struct LockPill: View {
    @ObservedObject var store: HostsStore
    @Binding var showPinUnlock: Bool
    @Binding var showPinSetup: Bool
    @Binding var showPasswordUnlock: Bool
    var onUnlock: () -> Void

    var body: some View {
        let unlocked = store.editingReady
        let preparing = store.isPreparing
        // Green when unlocked, red when locked; amber only during the brief unlock.
        let tint: Color = preparing ? Theme.amber : (unlocked ? Theme.green : Theme.red)
        Button {
            if preparing { return }
            if unlocked { store.lock() } else { onUnlock() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: preparing ? "touchid" : (unlocked ? "lock.open.fill" : "lock.fill"))
                    .font(.system(size: 12, weight: .bold))
                Text(preparing ? "Unlocking…" : (unlocked ? "Unlocked" : "Locked"))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 14).frame(height: 46)
            .background(tint.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.32), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(unlocked ? "Locked edits — click to lock now" : "Unlock edits for this session")
        .contextMenu {
            if store.pinSet {
                Button("Unlock with PIN…") { showPinUnlock = true }
                if store.sessionUnlocked {
                    Button("Change PIN…") { showPinSetup = true }
                    Button("Remove PIN") { confirmRemovePIN(store: store) }
                }
            } else if store.sessionUnlocked {
                Button("Set up PIN…") { showPinSetup = true }
            }
            if !store.sessionUnlocked {
                Button("Unlock with macOS Password…") { showPasswordUnlock = true }
            }
            Divider()
            Menu("Default unlock") {
                Picker("Default unlock", selection: $store.defaultUnlock) {
                    ForEach(UnlockMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Button("Reset session key…") { store.setupTouchID() }
        }
    }
}

// Accent-tinted "Update available" pill — same chrome as LockPill. Renders
// nothing until Sparkle's silent probe reports a newer version, so the normal
// header layout is untouched when the app is up to date. Tapping it launches
// Sparkle's standard install flow.
struct UpdatePill: View {
    @ObservedObject var updater = UpdaterManager.shared

    var body: some View {
        // Group + value-bound animation so the transition animates: UpdatePill
        // observes the updater, so its body re-renders when the flag flips and
        // the insertion/removal is wrapped in an easeOut transaction.
        Group {
            if updater.updateAvailable {
                Button { updater.checkForUpdates() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 12, weight: .bold))
                        Text(updater.latestVersion.map { "Update to \($0)" } ?? "Update available")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Theme.accent.opacity(0.13))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.accent.opacity(0.32), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .help("A new version is available — click to install")
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeOut, value: updater.updateAvailable)
    }
}

struct SegmentedFilter: View {
    @Binding var filter: Filter
    @ObservedObject var store: HostsStore

    private func count(_ f: Filter) -> Int {
        switch f {
        case .all: return store.entries.count
        case .active: return store.activeCount
        case .disabled: return store.entries.count - store.activeCount
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Filter.allCases, id: \.self) { f in
                let on = filter == f
                Button { filter = f } label: {
                    HStack(spacing: 6) {
                        Text(f.rawValue).font(.system(size: 13, weight: .semibold))
                        Text("\(count(f))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(on ? Theme.onAccent.opacity(0.9) : Theme.textDim)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background((on ? Theme.onAccent.opacity(0.2) : Theme.surface).opacity(on ? 1 : 0.6))
                            .clipShape(Capsule())
                    }
                    .foregroundColor(on ? Theme.onAccent : Theme.text2)
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(on ? AnyShapeStyle(LinearGradient.accentFill) : AnyShapeStyle(Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3).frame(height: 44)
        .background(Theme.surface2)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
