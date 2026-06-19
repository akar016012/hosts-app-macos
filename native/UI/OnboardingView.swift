// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import AppKit
import SwiftUI

// MARK: - Onboarding state

// Tracks whether the first-run walkthrough has been completed. Stored in
// UserDefaults so it shows exactly once per machine; "Replay welcome" in the
// profile menu flips it back so the tour can be re-watched on demand.
final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()
    private static let key = "hosts.onboarding.completed.v1"

    @Published var completed: Bool {
        didSet { UserDefaults.standard.set(completed, forKey: Self.key) }
    }

    // The current step lives here (not as view @State) so it survives the full
    // view-tree rebuild ContentView triggers when the theme changes — otherwise
    // picking a theme on the appearance step would snap back to the welcome step.
    @Published var step: OnboardingStep = .welcome

    private init() { completed = UserDefaults.standard.bool(forKey: Self.key) }

    func finish() { withAnimation(.easeInOut(duration: 0.28)) { completed = true } }
    func replay() {
        step = .welcome
        withAnimation(.easeInOut(duration: 0.28)) { completed = false }
    }
}

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome, profile, security, helper, appearance, star, ready

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .profile: return "person.crop.circle"
        case .security: return "lock.shield"
        case .helper: return "gearshape.2"
        case .appearance: return "paintpalette"
        case .star: return "star.fill"
        case .ready: return "checkmark.seal"
        }
    }
    var title: String {
        switch self {
        case .welcome: return "Welcome to Hosts"
        case .profile: return "Make it yours"
        case .security: return "Secure your edits"
        case .helper: return "Enable the helper"
        case .appearance: return "Pick a look"
        case .star: return "Star us on GitHub"
        case .ready: return "You're all set"
        }
    }
    var subtitle: String {
        switch self {
        case .welcome: return "Switch environments and manage your Mac's /etc/hosts file — fast and safe."
        case .profile: return "Add a name so the app feels like yours. Stays on this Mac — no account needed."
        case .security: return "Editing /etc/hosts is privileged. Choose how you'll unlock changes each session."
        case .helper: return "Hosts uses a tiny background helper to write /etc/hosts safely. macOS asks you to approve it once."
        case .appearance: return "Choose a theme. You can fine-tune or switch any time from your profile."
        case .star: return "Hosts is free and open source. A star helps other developers find it — and tells us it's worth improving."
        case .ready: return "Everything's ready. You can change any of this later from your profile menu."
        }
    }
}

// MARK: - Onboarding view

// Full-window first-run walkthrough, presented as an overlay on top of the main
// content. Each step writes straight into the existing stores (profile, unlock
// preference, optional PIN, theme) so finishing leaves the app fully configured.
struct OnboardingView: View {
    @ObservedObject var store: HostsStore
    @ObservedObject private var onboarding = OnboardingStore.shared
    @ObservedObject private var profile = ProfileStore.shared
    @ObservedObject private var themeStore = ThemeStore.shared

    // Backed by the store so it survives ContentView's theme-driven rebuild.
    private var step: OnboardingStep { onboarding.step }

    // Profile draft
    @State private var name = ""
    @State private var email = ""
    @State private var avatar: NSImage?
    @FocusState private var nameFocused: Bool

    // PIN draft (optional)
    @State private var pin = ""
    @State private var confirm = ""
    @State private var pinError: String? = nil

    var body: some View {
        ZStack {
            // Opaque backdrop + a soft accent glow so the card reads as a focused
            // modal regardless of the (locked) content behind it.
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.glow, .clear], center: .top,
                           startRadius: 0, endRadius: 620)
                .ignoresSafeArea()

            card
                .frame(width: 560)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { name = profile.name; email = profile.email; avatar = profile.avatar }
    }

    private var card: some View {
        VStack(spacing: 0) {
            heroIcon
            VStack(spacing: 8) {
                Text(step.title).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                Text(step.subtitle)
                    .font(.system(size: 13.5)).foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            .padding(.top, 18)

            content
                .padding(.top, 24)
                .frame(height: 290, alignment: .top)   // fixed (fits the tallest step) so the card doesn't jump or overlap
                .transition(.opacity)
                .id(step)

            progressDots.padding(.top, 18)
            footer.padding(.top, 20)
        }
        .padding(.horizontal, 36).padding(.top, 38).padding(.bottom, 28)
    }

    // MARK: Hero

    private var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.accentFill)
                .frame(width: 76, height: 76)
                .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 6)
            if step == .welcome {
                HostsLogoMark().frame(width: 76, height: 76)
            } else {
                Image(systemName: step.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
            }
        }
    }

    // MARK: Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:    welcomeContent
        case .profile:    profileContent
        case .security:   securityContent
        case .helper:     helperContent
        case .appearance: appearanceContent
        case .star:       starContent
        case .ready:      readyContent
        }
    }

    private var welcomeContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            advantageCard("rectangle.3.group", "Switch environments",
                          "Save local, staging, QA, and blocklists as schemes — switch in one click.")
            advantageCard("lock.shield", "Safe by default",
                          "Privileged writes to /etc/hosts are gated by Touch ID or a PIN.")
            advantageCard("clock.arrow.circlepath", "Undo anything",
                          "Every change is snapshotted — roll back to any version in a click.")
            advantageCard("square.and.pencil", "No terminal",
                          "Add, toggle, search, and bulk-edit host entries in a clean, fast UI.")
        }
    }

    private func advantageCard(_ icon: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accentSoft)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.accentBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(title).font(.system(size: 13.5, weight: .bold)).foregroundColor(Theme.text)
            Text(body).font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.surface2)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var profileContent: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 8) {
                AvatarEditor(image: $avatar, initials: previewInitials, size: 64, font: 22)
                Text("Add a photo").font(.system(size: 11)).foregroundColor(Theme.textDim)
            }
            VStack(spacing: 12) {
                onboardField("NAME", text: $name, placeholder: "Your name", focused: $nameFocused)
                onboardField("EMAIL (OPTIONAL)", text: $email, placeholder: "you@example.com", focused: nil)
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { nameFocused = true } }
    }

    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DEFAULT UNLOCK").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
                Picker("", selection: $store.defaultUnlock) {
                    ForEach(UnlockMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented)
                Text(store.touchIDAvailable
                     ? "Touch ID is available on this Mac. A PIN is a handy backup."
                     : "Touch ID isn't available here — set a PIN to unlock edits.")
                    .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SET A PIN (OPTIONAL)").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
                HStack(spacing: 10) {
                    onboardPinField("PIN", text: $pin)
                    onboardPinField("CONFIRM", text: $confirm)
                }
                if let pinError {
                    Text(pinError).font(.system(size: 11.5)).foregroundColor(Theme.red)
                } else {
                    Text("\(PinStore.minLength)–\(PinStore.maxLength) digits. Leave blank to skip.")
                        .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                }
            }
        }
    }

    private var helperContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                helperBullet("shield.lefthalf.filled",
                             "A small background helper makes the actual write, so the app never runs as root.")
                helperBullet("hand.raised.fill",
                             "macOS asks you to switch it on once in System Settings → Login Items — no password needed.")
                helperBullet("arrow.uturn.backward",
                             "Remove it anytime from the Hosts menu or Login Items.")
            }

            Button { store.registerHelper() } label: {
                Label(store.helperRegistered ? "Helper enabled" : "Enable helper…",
                      systemImage: store.helperRegistered ? "checkmark.circle.fill" : "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            .disabled(store.helperRegistered)

            Text(store.helperRegistered
                 ? "Approved and running — you're good to go."
                 : "Opens System Settings → Login Items. Switch “Hosts” on, then come back. You can also do this later at your first edit.")
                .font(.system(size: 11.5))
                .foregroundColor(store.helperRegistered ? Theme.green : Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { store.refreshHelperStatus() }
        // The user leaves the app to toggle "Hosts" on in System Settings →
        // Login Items, then comes back. .onAppear won't fire again on that
        // return, so re-poll whenever the app regains focus to catch the change.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshHelperStatus()
        }
    }

    private func helperBullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.accent).frame(width: 20)
            Text(text).font(.system(size: 12.5)).foregroundColor(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(1.5)
            Spacer(minLength: 0)
        }
    }

    private var appearanceContent: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 14) {
                ForEach(AppTheme.presets) { t in
                    let on = themeStore.theme == t
                    Button { themeStore.theme = t } label: {
                        VStack(spacing: 5) {
                            Circle().fill(t.dot)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(on ? Theme.accent : .white.opacity(0.14),
                                                         lineWidth: on ? 2.5 : 1))
                                .overlay {
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .black))
                                            .foregroundColor(t.palette.isLight ? .black.opacity(0.7) : .white)
                                    }
                                }
                            Text(t.label).font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(on ? Theme.text : Theme.textDim)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Want full control? Build a custom theme later from your profile menu.")
                .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
        }
    }

    // Open-source nudge: invite the user to star the repo and contribute. Opening
    // the link is optional — "Continue" advances regardless.
    private static let repoURLString = "https://github.com/akar016012/hosts-app-macos"

    private var starContent: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 11) {
                helperBullet("chevron.left.forwardslash.chevron.right",
                             "Hosts is free and fully open source — you can read every line that touches /etc/hosts.")
                helperBullet("star.fill",
                             "A GitHub star helps other developers find Hosts and keeps the project moving.")
                helperBullet("exclamationmark.bubble.fill",
                             "Hit a bug or have an idea? Open an issue or a pull request anytime.")
            }

            Button { openRepo() } label: {
                Label("Star on GitHub", systemImage: "star.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())

            Text(Self.repoURLString)
                .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textDim)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openRepo() {
        guard let url = URL(string: Self.repoURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryRow("person.crop.circle",
                       profile.isSignedIn ? "Signed in as \(profile.trimmedName)" : "Using Hosts as a guest")
            summaryRow("lock.shield", "Default unlock: \(store.defaultUnlock.label)"
                       + (store.pinSet ? " · PIN set" : ""))
            summaryRow("gearshape.2",
                       store.helperRegistered ? "Privileged helper enabled" : "Helper not enabled — enable at first edit",
                       ok: store.helperRegistered)
            summaryRow("paintpalette", "Theme: \(themeStore.theme.label)")
            Text("Tip: save setups as Schemes (⌘L) and switch them from the menu bar.")
                .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { store.refreshHelperStatus() }
        // Keep the summary honest if the helper is enabled while this step is up
        // (e.g. enabled on the previous step, then returned from System Settings).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshHelperStatus()
        }
    }

    // MARK: Progress + footer

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? Theme.accent : Theme.border)
                    .frame(width: s == step ? 20 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { back() }.buttonStyle(SoftButton())
            }
            Spacer()
            if step != .welcome && step != .ready {
                Button("Skip for now") { onboarding.finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.textDim)
            }
            Button(primaryLabel) { advance() }.buttonStyle(PrimaryButton())
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Get started"
        case .ready: return "Start using Hosts"
        default: return "Continue"
        }
    }

    // MARK: Navigation

    private func back() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        pinError = nil
        withAnimation(.easeInOut(duration: 0.2)) { onboarding.step = prev }
    }

    private func advance() {
        // Commit the current step's input before moving on.
        switch step {
        case .profile:
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if avatar !== profile.avatar { profile.setAvatar(avatar) }
        case .security:
            if !commitPINIfNeeded() { return }   // validation failed; stay put
        default:
            break
        }

        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            onboarding.finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { onboarding.step = next }
    }

    // Saves the optional PIN. Returns false (and sets an error) when the user
    // started entering one but it's invalid or mismatched; true when saved or
    // intentionally left blank.
    private func commitPINIfNeeded() -> Bool {
        pinError = nil
        if pin.isEmpty && confirm.isEmpty { return true }
        if let reason = PinStore.validate(pin) { pinError = reason; return false }
        guard pin == confirm else { pinError = "PINs don't match."; return false }
        if let reason = store.setPIN(pin) { pinError = reason; return false }
        return true
    }

    // MARK: Building blocks

    private var previewInitials: String {
        let words = name.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "-" })
        if words.count >= 2 { return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
        if let first = words.first { return String(first.prefix(2)).uppercased() }
        return ""
    }

    private func summaryRow(_ icon: String, _ text: String, ok: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.accent).frame(width: 20)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text2)
            Spacer(minLength: 0)
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 14)).foregroundColor(ok ? Theme.green : Theme.textDim)
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(Theme.surface2)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func onboardField(_ label: String, text: Binding<String>, placeholder: String,
                              focused: FocusState<Bool>.Binding?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
            let tf = TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                .padding(.horizontal, 12).frame(height: 44).background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if let focused { tf.focused(focused) } else { tf }
        }
    }

    private func onboardPinField(_ label: String, text: Binding<String>) -> some View {
        // Digits-only, capped at the max length — mirrors the PIN sheet's field.
        let sanitized = Binding(get: { text.wrappedValue },
                                set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(PinStore.maxLength)) })
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
            SecureField("••••", text: sanitized)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
                .padding(.horizontal, 12).frame(height: 44).background(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
