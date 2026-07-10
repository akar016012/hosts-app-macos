// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import SwiftUI

// MARK: - Reusable avatar

// Renders the profile picture when one is set, otherwise the gradient initials
// (or a generic glyph when there's no name yet). Always clipped to a circle so
// every call site stays consistent.
struct ProfileAvatar: View {
    let image: NSImage?
    let initials: String   // empty -> show the generic person glyph
    var size: CGFloat
    var font: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(LinearGradient.accentFill)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: font, weight: .semibold))
                        .foregroundColor(Theme.onAccent.opacity(0.9))
                } else {
                    Text(initials)
                        .font(.system(size: font, weight: .bold))
                        .foregroundColor(Theme.onAccent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Avatar editor

// An avatar with a camera badge that opens a menu to choose or remove the
// profile picture. Drives a draft NSImage binding so the choice can be committed
// (or discarded) by the surrounding sheet/flow.
struct AvatarEditor: View {
    @Binding var image: NSImage?
    let initials: String
    var size: CGFloat
    var font: CGFloat

    var body: some View {
        ProfileAvatar(image: image, initials: initials, size: size, font: font)
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Button(image == nil ? "Choose photo…" : "Change photo…") {
                        if let picked = AvatarPicker.pick() { image = picked }
                    }
                    if image != nil {
                        Button("Remove photo", role: .destructive) { image = nil }
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: size * 0.26, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(Circle().fill(LinearGradient.accentFill))
                        .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Change profile picture")
                .offset(x: size * 0.06, y: size * 0.06)
            }
    }
}

// MARK: - Profile badge (header avatar)

// The round initials avatar shown at the end of the header. Click to open the
// Profile menu, which gathers identity, preferences, and security in one place.
struct ProfileBadge: View {
    @ObservedObject private var profile = ProfileStore.shared
    @Binding var showProfile: Bool
    @ObservedObject var store: HostsStore
    @Binding var showProfileEdit: Bool
    @Binding var showPinSetup: Bool
    @Binding var showThemeEditor: Bool
    @State private var hovering = false

    var body: some View {
        Button { showProfile.toggle() } label: {
            avatar(size: 40, font: 14)
                .overlay(Circle().stroke(.white.opacity(hovering ? 0.35 : 0.18), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    // A small dot mirrors the lock state so identity and access
                    // are readable at a glance without opening the menu.
                    Circle().fill(store.editingReady ? Theme.green : Theme.red)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Theme.headerBg, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(profile.isSignedIn ? "\(profile.trimmedName) — profile & settings" : "Set up your profile")
        .popover(isPresented: $showProfile, arrowEdge: .bottom) {
            ProfileMenu(store: store, isPresented: $showProfile,
                        showProfileEdit: $showProfileEdit, showPinSetup: $showPinSetup,
                        showThemeEditor: $showThemeEditor)
        }
    }

    @ViewBuilder
    private func avatar(size: CGFloat, font: CGFloat) -> some View {
        ProfileAvatar(image: profile.avatar,
                      initials: profile.isSignedIn ? profile.initials : "",
                      size: size, font: font)
    }
}

// MARK: - Profile menu (popover)

// Identity header + preferences + security, styled like ThemeMenu. Actions that
// open a sheet first close this popover to avoid a SwiftUI presentation conflict.
struct ProfileMenu: View {
    @ObservedObject var store: HostsStore
    @ObservedObject private var profile = ProfileStore.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var updater = UpdaterManager.shared
    @Binding var isPresented: Bool
    @Binding var showProfileEdit: Bool
    @Binding var showPinSetup: Bool
    @Binding var showThemeEditor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityHeader

            Group {
                sectionLabel("APPEARANCE")
                themeSwatches
                customThemeRow
                sectionLabel("PREFERENCES")
                unlockRow
            }

            divider

            Group {
                sectionLabel("SECURITY")
                autoLockRow
                if store.pinSet {
                    // Managing an existing PIN requires an unlocked session —
                    // same gate as the LockPill context menu.
                    if store.sessionUnlocked {
                        menuRow("Change PIN", icon: "number.square.fill") { present { showPinSetup = true } }
                        menuRow("Remove PIN", icon: "trash", danger: true) {
                            close(); confirmRemovePIN(store: store)
                        }
                    }
                } else if store.sessionUnlocked {
                    menuRow("Set up a PIN", icon: "number.square.fill") { present { showPinSetup = true } }
                }
                menuRow("Reset session key", icon: "arrow.triangle.2.circlepath") {
                    close(); store.setupTouchID()
                }
            }

            divider

            menuRow("Replay welcome tour", icon: "sparkles") {
                close(); OnboardingStore.shared.replay()
            }
            menuRow("Check for updates", icon: "arrow.down.circle") {
                close(); updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
        .padding(6).frame(width: 330)
        .background(Theme.surface.opacity(0.95))
        .background(.ultraThinMaterial)
    }

    // MARK: Header

    private var identityHeader: some View {
        Button { present { showProfileEdit = true } } label: {
            HStack(spacing: 11) {
                ProfileAvatar(image: profile.avatar,
                              initials: profile.isSignedIn ? profile.initials : "",
                              size: 42, font: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.isSignedIn ? profile.trimmedName : "Set up your profile")
                        .font(.system(size: 14.5, weight: .bold)).foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(profile.isSignedIn && !profile.email.isEmpty ? profile.email
                            : (profile.isSignedIn ? "Edit name & email" : "Add your name to personalize"))
                        .font(.system(size: 11.5)).foregroundColor(Theme.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.textDim)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(Theme.surface2.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    // MARK: Appearance — compact theme swatches

    private var themeSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(AppTheme.presets) { t in
                let on = themeStore.theme == t
                Button { themeStore.theme = t } label: {
                    Circle().fill(t.dot)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(on ? Theme.accent : .white.opacity(0.12),
                                                 lineWidth: on ? 2 : 1))
                        .overlay {
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(t.palette.isLight ? .black.opacity(0.7) : .white)
                            }
                        }
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.label)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: Appearance — custom theme

    private var customThemeRow: some View {
        let isActive = themeStore.theme == .custom
        return Button { present { showThemeEditor = true } } label: {
            HStack(spacing: 10) {
                // A two-stop gradient chip previews the custom accent.
                Circle()
                    .fill(LinearGradient(colors: [CustomTheme.accent.brightnessAdjusted(0.12), CustomTheme.accent],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(isActive ? Theme.accent : .white.opacity(0.14),
                                             lineWidth: isActive ? 2 : 1))
                Text("Custom theme").font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.accent)
                }
                Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textDim)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButton())
    }

    // MARK: Preferences — default unlock

    private var unlockRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.rotation").font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textDim).frame(width: 18)
            Text("Default unlock").font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            Picker("", selection: $store.defaultUnlock) {
                ForEach(UnlockMethod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .tint(Theme.accent)
        }
        .padding(.horizontal, 12).frame(height: 40)
    }

    // MARK: Security — auto-lock timeout

    private var autoLockRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer").font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textDim).frame(width: 18)
            Text("Auto-lock").font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
            Spacer()
            Picker("", selection: $store.autoLockMinutes) {
                Text("Never").tag(0)
                Text("1 min").tag(1)
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .tint(Theme.accent)
        }
        .padding(.horizontal, 12).frame(height: 40)
    }

    // MARK: Building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).tracking(0.6)
            .foregroundColor(Theme.textDim)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
            .padding(.vertical, 5).padding(.horizontal, 12)
    }

    private func menuRow(_ title: String, icon: String, danger: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(danger ? Theme.red : Theme.textDim).frame(width: 18)
                Text(title).font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(danger ? Theme.red : Theme.text)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButton())
    }

    // Close the popover, optionally scheduling a follow-up sheet after it has
    // dismissed so the two presentations don't fight each other.
    private func close() { isPresented = false }
    private func present(_ open: @escaping () -> Void) {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: open)
    }
}

// Row button with a subtle hover fill, matching the menu aesthetic.
private struct MenuRowButton: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background((hovering || configuration.isPressed) ? Theme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering = $0 }
    }
}

// MARK: - Edit profile sheet

// Set the local display name and optional email. Saving with a blank name signs
// out (clears the profile); the avatar falls back to the generic person glyph.
struct ProfileEditSheet: View {
    @ObservedObject private var profile = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var avatar: NSImage?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                AvatarEditor(image: $avatar, initials: previewInitials, size: 52, font: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.isSignedIn ? "Edit profile" : "Set up your profile")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                    Text("Stored locally on this Mac — no account needed.")
                        .font(.system(size: 12)).foregroundColor(Theme.textDim)
                }
            }

            field("NAME", text: $name, placeholder: "Your name", focused: $nameFocused)
            field("EMAIL (OPTIONAL)", text: $email, placeholder: "you@example.com", focused: nil)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Save") { save() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 420).background(Theme.surface)
        .onAppear { name = profile.name; email = profile.email; avatar = profile.avatar; nameFocused = true }
    }

    private var previewInitials: String {
        let words = name.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "-" })
        if words.count >= 2 { return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
        if let first = words.first { return String(first.prefix(2)).uppercased() }
        return ""
    }

    private func save() {
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if avatar !== profile.avatar { profile.setAvatar(avatar) }
        dismiss()
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String,
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
}

// MARK: - Custom theme editor

// Pick an accent color and a light/dark base; the rest of the palette is derived
// from a built-in template so contrast stays readable. The preview card is drawn
// from the local picks (not the live theme) so dragging the picker stays smooth;
// "Apply" commits the choice and switches the app to the custom theme.
struct CustomThemeSheet: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var data: CustomThemeData = CustomThemeData.current
    @State private var resetConfirm = false

    // Quick-pick swatches for the seed accent.
    private let accentSuggestions = ["5b8cff", "34d399", "a78bfa", "f43f5e", "38bdf8", "fb923c", "f5b54a", "2dd4bf"]

    private var seedPreset: AppTheme {
        AppTheme(rawValue: data.basePresetRaw) ?? (data.isLight ? .daylight : .midnight)
    }

    private var defaults: [ThemeToken: Color] {
        AppTheme.customDefaults(basePreset: seedPreset,
                                accent: Color(hex: data.accentHex),
                                isLight: data.isLight)
    }

    // Drawn from local picks so dragging stays smooth and the live app palette
    // isn't touched until Apply.
    private var livePalette: Palette { AppTheme.customPalette(from: data) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            preview
            seedRow
            Divider().background(Theme.border)
            tokenList
            footer
        }
        .padding(20)
        .frame(width: 560, height: 720)
        .background(Theme.surface)
    }

    // MARK: layout pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Custom theme").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            Text("Seed from a preset + accent, then override any individual color.")
                .font(.system(size: 12)).foregroundColor(Theme.textDim)
        }
    }

    private var seedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Base").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text2)
                Picker("", selection: $data.basePresetRaw) {
                    ForEach(AppTheme.presets) { t in
                        Text(t.label).tag(t.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()

                Spacer()

                Picker("", selection: $data.isLight) {
                    Text("Dark").tag(false)
                    Text("Light").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }

            HStack(spacing: 10) {
                ColorPicker(selection: Binding(
                    get: { Color(hex: data.accentHex) },
                    set: { data.accentHex = $0.hexString }
                ), supportsOpacity: false) {
                    Text("Seed accent").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text2)
                }
                Spacer()
                ForEach(accentSuggestions, id: \.self) { hex in
                    Button { data.accentHex = hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("#\(hex)")
                }
            }
        }
    }

    private var tokenList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(TokenGroup.allCases, id: \.self) { group in
                    section(for: group)
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func section(for group: TokenGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.label.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundColor(Theme.textDim)
            VStack(spacing: 4) {
                ForEach(group.tokens, id: \.self) { tok in
                    tokenRow(tok)
                }
            }
            .padding(8)
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func tokenRow(_ token: ThemeToken) -> some View {
        let isOverridden = data.hasOverride(token)
        let current = data.color(for: token, defaults: defaults)
        let binding = Binding<Color>(
            get: { current },
            set: { newValue in
                data.overrides[token.rawValue] = token.supportsOpacity
                    ? newValue.hexStringRGBA
                    : newValue.hexString
            }
        )
        return HStack(spacing: 10) {
            // Swatch with a checkerboard underlay so alpha tokens read at a glance.
            ZStack {
                if token.supportsOpacity { CheckerboardPattern() }
                Rectangle().fill(current)
            }
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(token.label).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.text)
                Text(token.rawValue).font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            }

            Spacer()

            if isOverridden {
                Button {
                    data.overrides.removeValue(forKey: token.rawValue)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textDim)
                        .frame(width: 22, height: 22)
                        .background(Theme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Reset to derived default")
            }

            ColorPicker("", selection: binding, supportsOpacity: token.supportsOpacity)
                .labelsHidden().frame(width: 36)
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                resetConfirm = true
            } label: {
                Text("Reset all overrides").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(data.overrides.isEmpty ? Theme.textMut : Theme.text2)
            }
            .buttonStyle(.plain)
            .disabled(data.overrides.isEmpty)
            .confirmationDialog("Clear every per-token override?",
                                isPresented: $resetConfirm) {
                Button("Clear overrides", role: .destructive) { data.overrides.removeAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Tokens will revert to values derived from the base preset + accent.")
            }

            if !data.overrides.isEmpty {
                Text("\(data.overrides.count) overridden")
                    .font(.system(size: 11)).foregroundColor(Theme.textDim)
            }

            Spacer()

            Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
            Button("Apply") {
                themeStore.applyCustom(data)
                dismiss()
            }.buttonStyle(PrimaryButton())
        }
    }

    // MARK: preview

    // Realistic mock of the header / list rows / button / semantic chips drawn
    // from the local palette so users see the effect of every pick live.
    private var preview: some View {
        let p = livePalette
        let grad = LinearGradient(colors: [p.accent2, p.accent],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(grad).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(p.onAccent))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Preview").font(.system(size: 12, weight: .semibold)).foregroundColor(p.text)
                    Text("hosts.local").font(.system(size: 10)).foregroundColor(p.textDim)
                }
                Spacer()
                Text("Button").font(.system(size: 11, weight: .bold)).foregroundColor(p.onAccent)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(grad)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(p.headerBg)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            VStack(spacing: 0) {
                previewRow("api.example.com", on: true, p: p)
                Rectangle().fill(p.rowBorder).frame(height: 1)
                previewRow("staging.disabled", on: false, p: p)
            }

            HStack(spacing: 8) {
                chip("OK", color: p.green)
                chip("Warn", color: p.amber)
                chip("Fail", color: p.red)
                Spacer()
                Text("Aa")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.accent)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(p.accentSoft)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.accentBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(p.surface2)
        }
        .background(p.bg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func previewRow(_ host: String, on: Bool, p: Palette) -> some View {
        HStack {
            Circle().fill(on ? p.accent : p.toggleOff).frame(width: 8, height: 8)
            Text(host).font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundColor(on ? p.text : p.text2)
            Spacer()
            Text(on ? "127.0.0.1" : "—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(p.textDim)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(on ? p.row : p.rowOff)
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label).font(.system(size: 10, weight: .bold))
            .foregroundColor(Theme.readable(on: color))
            .padding(.horizontal, 7).frame(height: 20)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// Faint two-tone checkerboard rendered behind translucent swatches so alpha
// reads at a glance.
private struct CheckerboardPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 6
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile,
                                      width: tile, height: tile)
                    ctx.fill(Path(rect), with: .color(.gray.opacity(0.35)))
                }
            }
        }
        .background(Color.white.opacity(0.85))
    }
}
