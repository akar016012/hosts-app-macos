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

    enum NavDirection { case forward, backward }

    // Navigation state lives here (not as view @State) so it survives the full
    // view-tree rebuild ContentView triggers when the theme changes — otherwise
    // picking a theme on the appearance step would snap back to the welcome step.
    @Published var step: OnboardingStep = .welcome
    @Published var direction: NavDirection = .forward
    @Published var maxVisited: OnboardingStep = .welcome

    private init() { completed = UserDefaults.standard.bool(forKey: Self.key) }

    func finish() { withAnimation(.easeInOut(duration: 0.28)) { completed = true } }
    func replay() {
        step = .welcome
        direction = .forward
        maxVisited = .welcome
        withAnimation(.easeInOut(duration: 0.28)) { completed = false }
    }

    // Single navigation entry point. Direction is set synchronously before the
    // animated step change so both the inserted and the removed step views
    // resolve their transition against the correct edge.
    func go(to target: OnboardingStep) {
        guard target != step else { return }
        direction = target.rawValue > step.rawValue ? .forward : .backward
        if target.rawValue > maxVisited.rawValue { maxVisited = target }
        withAnimation(.easeInOut(duration: 0.3)) { step = target }
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

    // Measured natural height of the current step's body. nil (first layout,
    // or right after a theme rebuild) means "size naturally" — which is exactly
    // what the measurement will confirm, so there's never a visible jump.
    @State private var measuredHeight: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Opaque backdrop + a soft accent glow so the card reads as a focused
                // modal regardless of the (locked) content behind it.
                Theme.bg.ignoresSafeArea()
                RadialGradient(colors: [Theme.glow, .clear], center: .top,
                               startRadius: 0, endRadius: 620)
                    .ignoresSafeArea()

                card(availableHeight: geo.size.height)
                    .frame(width: 560)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { name = profile.name; email = profile.email; avatar = profile.avatar }
    }

    private func card(availableHeight: CGFloat) -> some View {
        // Everything around the step body — card paddings, hero, dots, footer —
        // is ~260pt of chrome. Whatever the window leaves after that caps the
        // step region; with the 720pt window minimum this never bites, it's a
        // safety net that degrades tall content to scrolling, never to overlap.
        let cap = max(160, availableHeight - 260)
        return VStack(spacing: 0) {
            heroIcon
            stepPager(cap: cap).padding(.top, 18)
            progressDots.padding(.top, 18)
            footer.padding(.top, 20)
        }
        .padding(.horizontal, 36).padding(.top, 38).padding(.bottom, 28)
        // The counter lives in the card's corner, not above the title, so the
        // logo → title distance is identical on every step.
        .overlay(alignment: .topTrailing) { stepCounter.padding(18) }
    }

    @ViewBuilder
    private var stepCounter: some View {
        if step != .welcome {
            Text("STEP \(step.rawValue + 1) OF \(OnboardingStep.allCases.count)")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundColor(Theme.textDim)
        }
    }

    // The swappable region: title + subtitle + step content slide as one unit,
    // and its frame animates to each step's measured natural height. The ZStack
    // is load-bearing — while a transition is in flight the outgoing and
    // incoming steps coexist, and they must overlay, not stack vertically.
    private func stepPager(cap: CGFloat) -> some View {
        ZStack(alignment: .top) {
            stepBody
                .id(step)
                .transition(stepTransition)
                .background(HeightReporter(step: step))
        }
        .frame(maxWidth: .infinity)
        .frame(height: measuredHeight.map { min($0, cap) }, alignment: .top)
        .clipped()   // overflow can never paint over the dots
        .onPreferenceChange(StepHeightKey.self) { heights in
            // Both the outgoing and incoming steps report while a transition is
            // in flight — only the current step's entry may drive the frame.
            guard let h = heights[step.rawValue] else { return }
            if measuredHeight == nil {
                measuredHeight = h   // first layout: matches natural size, no jump
            } else if h != measuredHeight {
                withAnimation(.easeInOut(duration: 0.3)) { measuredHeight = h }
            }
        }
    }

    private var stepBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(step.title).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                Text(step.subtitle)
                    .font(.system(size: 13.5)).foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            content.padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepTransition: AnyTransition {
        // A short directional offset + fade; a full-width .move would fight the
        // clipped edges at this card size.
        let fwd = onboarding.direction == .forward
        return .asymmetric(
            insertion: .offset(x: fwd ? 36 : -36).combined(with: .opacity),
            removal: .offset(x: fwd ? -36 : 36).combined(with: .opacity))
    }

    // MARK: Hero

    // The gradient tile stays fixed as the visual anchor; only the glyph swaps,
    // cross-scaling with the step change.
    private var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.accentFill)
                .frame(width: 76, height: 76)
                .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 6)
            heroGlyph
                .id(step)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var heroGlyph: some View {
        if step == .welcome {
            HostsLogoMark().frame(width: 76, height: 76)
        } else {
            Image(systemName: step.icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(Theme.onAccent)
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
        // Eager Grid, not LazyVGrid — lazy cells materialize after layout and
        // would mis-report the step's height to the animated card frame.
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                AdvantageCard(icon: "rectangle.3.group", title: "Switch environments",
                              text: "Save local, staging, QA, and blocklists as schemes — switch in one click.")
                    .modifier(StaggeredAppear(index: 0))
                AdvantageCard(icon: "lock.shield", title: "Safe by default",
                              text: "Privileged writes to /etc/hosts are gated by Touch ID, a PIN, or your macOS password.")
                    .modifier(StaggeredAppear(index: 1))
            }
            GridRow {
                AdvantageCard(icon: "clock.arrow.circlepath", title: "Undo anything",
                              text: "Every change is snapshotted — roll back to any version in a click.")
                    .modifier(StaggeredAppear(index: 2))
                AdvantageCard(icon: "square.and.pencil", title: "No terminal",
                              text: "Add, toggle, search, and bulk-edit host entries in a clean, fast UI.")
                    .modifier(StaggeredAppear(index: 3))
            }
        }
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
                    ForEach(UnlockMethod.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented)
                Text(store.touchIDAvailable
                     ? "Touch ID is available on this Mac. A PIN or your macOS login password also works."
                     : "Touch ID isn't available here — use your macOS login password, or set a PIN below.")
                    .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
            }

            // On a tour replay with a PIN already set, changing it requires an
            // unlocked session (store guard) — point at the profile menu instead
            // of offering fields that would be rejected.
            if store.pinSet {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PIN").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
                    Text("A PIN is already set. Change or remove it from the profile menu\(store.sessionUnlocked ? "" : " after unlocking").")
                        .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
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
    }

    private var helperContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                helperBullet("shield.lefthalf.filled",
                             "A small background helper makes the actual write, so the app never runs as root.")
                    .modifier(StaggeredAppear(index: 0))
                helperBullet("hand.raised.fill",
                             "macOS asks you to switch it on once in System Settings → Login Items — no password needed.")
                    .modifier(StaggeredAppear(index: 1))
                helperBullet("arrow.uturn.backward",
                             "Remove it anytime from the Hosts menu or Login Items.")
                    .modifier(StaggeredAppear(index: 2))
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
                    .modifier(StaggeredAppear(index: 0))
                helperBullet("star.fill",
                             "A GitHub star helps other developers find Hosts and keeps the project moving.")
                    .modifier(StaggeredAppear(index: 1))
                helperBullet("exclamationmark.bubble.fill",
                             "Hit a bug or have an idea? Open an issue or a pull request anytime.")
                    .modifier(StaggeredAppear(index: 2))
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
                .modifier(StaggeredAppear(index: 0))
            summaryRow("lock.shield", "Default unlock: \(store.defaultUnlock.label)"
                       + (store.pinSet ? " · PIN set" : ""))
                .modifier(StaggeredAppear(index: 1))
            summaryRow("gearshape.2",
                       store.helperRegistered ? "Privileged helper enabled" : "Helper not enabled — enable at first edit",
                       ok: store.helperRegistered)
                .modifier(StaggeredAppear(index: 2))
            summaryRow("paintpalette", "Theme: \(themeStore.theme.label)")
                .modifier(StaggeredAppear(index: 3))
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

    // Visited dots double as navigation: click to jump back (or forward, up to
    // the furthest step reached). Jumps don't run per-step commits — same
    // contract as the Back button; Continue is the sole commit point.
    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                let visited = s.rawValue <= onboarding.maxVisited.rawValue
                Button { jump(to: s) } label: {
                    Capsule()
                        .fill(s == step ? Theme.accent
                              : (visited ? Theme.textDim.opacity(0.55) : Theme.border))
                        .frame(width: s == step ? 20 : 7, height: 7)
                        .contentShape(Rectangle().inset(by: -5))   // comfortable hit target
                }
                .buttonStyle(.plain)
                .disabled(!visited || s == step)
                .help(visited ? s.title : "")
                .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { back() }
                    .buttonStyle(SoftButton())
                    .keyboardShortcut(.cancelAction)
                // ⌘← twin — a button carries only one shortcut. Kept in the tree
                // via .opacity(0) rather than .hidden(): hidden buttons don't
                // reliably keep their shortcut registered.
                Button("", action: back)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            Spacer()
            if step != .welcome && step != .ready {
                Button("Skip for now") { onboarding.finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.textDim)
            }
            Button(primaryLabel) { advance() }
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)   // Return advances, even from a focused field
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
        onboarding.go(to: prev)
    }

    private func jump(to target: OnboardingStep) {
        guard target.rawValue <= onboarding.maxVisited.rawValue, target != step else { return }
        pinError = nil
        onboarding.go(to: target)
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
        onboarding.go(to: next)
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

// MARK: - Supporting pieces

// Welcome feature card. A struct (not a builder function) so it can hold the
// hover state — on hover the border and a soft accent wash light up, matching
// the SoftButton(active:) / theme-swatch idiom. No scale: informational, not a button.
private struct AdvantageCard: View {
    let icon: String
    let title: String
    let text: String
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accentSoft)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.accentBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(title).font(.system(size: 13.5, weight: .bold)).foregroundColor(Theme.text)
            Text(text).font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(ZStack {
            Theme.surface2
            Theme.accentSoft.opacity(hovering ? 0.6 : 0)
        })
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(hovering ? Theme.accentBorder : Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// Staggered entrance: fade + a small rise, delayed per index so list items
// cascade in after the step's slide-in transition has mostly settled. Animates
// opacity/offset only — never layout — so it can't disturb the card's height
// measurement. Deliberately NOT used on the appearance step: theme clicks
// rebuild the view tree and would replay the entrance on every swatch click.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(0.15 + Double(index) * 0.06)) {
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

// Reports each step's natural content height, keyed by step, so the card can
// animate to the incoming step's height while ignoring the outgoing view's
// report during a transition.
private struct StepHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private struct HeightReporter: View {
    let step: OnboardingStep
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: StepHeightKey.self,
                                   value: [step.rawValue: g.size.height])
        }
    }
}
