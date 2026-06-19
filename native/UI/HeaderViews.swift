import SwiftUI

// MARK: - Header components

struct ThemeMenu: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("THEME").font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundColor(Theme.textDim).padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ForEach(AppTheme.allCases) { t in
                Button { themeStore.theme = t } label: {
                    HStack(spacing: 11) {
                        Circle().fill(t.dot).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                        Text(t.label).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        if themeStore.theme == t {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(themeStore.theme == t ? Theme.accentSoft : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6).frame(width: 230)
        .background(Theme.surface)
    }
}

struct LockPill: View {
    @ObservedObject var store: HostsStore
    var body: some View {
        let unlocked = store.editingReady
        let preparing = store.isPreparing
        let tint: Color = preparing ? Theme.amber : (unlocked ? Theme.green : Theme.amber)
        Button {
            if preparing { return }
            if unlocked { store.lock() } else { store.unlockSession() }
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
        .help(unlocked ? "Locked edits — click to lock now" : "Unlock edits for this session (Touch ID)")
        .contextMenu { Button("Reset session key…") { store.setupTouchID() } }
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
                            .foregroundColor(on ? .white.opacity(0.9) : Theme.textDim)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background((on ? Color.white.opacity(0.2) : Theme.surface).opacity(on ? 1 : 0.6))
                            .clipShape(Capsule())
                    }
                    .foregroundColor(on ? .white : Theme.text2)
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
