import SwiftUI

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
        ZStack {
            Circle().fill(LinearGradient.accentFill)
            if profile.isSignedIn {
                Text(profile.initials)
                    .font(.system(size: font, weight: .bold)).foregroundColor(Theme.onAccent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: font, weight: .semibold)).foregroundColor(Theme.onAccent.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Profile menu (popover)

// Identity header + preferences + security, styled like ThemeMenu. Actions that
// open a sheet first close this popover to avoid a SwiftUI presentation conflict.
struct ProfileMenu: View {
    @ObservedObject var store: HostsStore
    @ObservedObject private var profile = ProfileStore.shared
    @ObservedObject private var themeStore = ThemeStore.shared
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
                if store.pinSet {
                    menuRow("Change PIN", icon: "number.square.fill") { present { showPinSetup = true } }
                    menuRow("Remove PIN", icon: "trash", danger: true) { store.removePIN() }
                } else {
                    menuRow("Set up a PIN", icon: "number.square.fill") { present { showPinSetup = true } }
                }
                menuRow("Reset session key", icon: "arrow.triangle.2.circlepath") {
                    close(); store.setupTouchID()
                }
            }

            if profile.isSignedIn {
                divider
                menuRow("Sign out", icon: "rectangle.portrait.and.arrow.right", danger: true) {
                    close(); profile.signOut()
                }
            }
        }
        .padding(6).frame(width: 256)
        .background(Theme.surface.opacity(0.95))
        .background(.ultraThinMaterial)
    }

    // MARK: Header

    private var identityHeader: some View {
        Button { present { showProfileEdit = true } } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(LinearGradient.accentFill)
                    if profile.isSignedIn {
                        Text(profile.initials).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.onAccent)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.onAccent.opacity(0.9))
                    }
                }
                .frame(width: 42, height: 42)
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
            Spacer()
            Picker("", selection: $store.defaultUnlock) {
                ForEach(UnlockMethod.allCases, id: \.self) { Text($0.label).tag($0) }
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
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(LinearGradient.accentFill)
                    let preview = previewInitials
                    if preview.isEmpty {
                        Image(systemName: "person.fill").font(.system(size: 18, weight: .semibold)).foregroundColor(Theme.onAccent.opacity(0.9))
                    } else {
                        Text(preview).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.onAccent)
                    }
                }
                .frame(width: 52, height: 52)
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
                if profile.isSignedIn {
                    Button("Sign out") { profile.signOut(); dismiss() }
                        .buttonStyle(SoftButton(danger: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Save") { save() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 420).background(Theme.surface)
        .onAppear { name = profile.name; email = profile.email; nameFocused = true }
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

    @State private var accent: Color = CustomTheme.accent
    @State private var isLight = CustomTheme.isLight

    // A few tasteful starting points for the color well.
    private let suggestions = ["5b8cff", "34d399", "a78bfa", "f43f5e", "38bdf8", "fb923c", "f5b54a", "2dd4bf"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom theme").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                Text("Pick an accent color and base — the rest is derived for you.")
                    .font(.system(size: 12)).foregroundColor(Theme.textDim)
            }

            preview

            HStack(spacing: 12) {
                ColorPicker(selection: $accent, supportsOpacity: false) {
                    Text("Accent color").font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                }
                Spacer()
                Picker("", selection: $isLight) {
                    Text("Dark").tag(false)
                    Text("Light").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }

            // Quick accent suggestions.
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { hex in
                    Button { accent = Color(hex: hex) } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Apply") {
                    themeStore.applyCustom(accentHex: accent.hexString, isLight: isLight)
                    dismiss()
                }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 420).background(Theme.surface)
    }

    // Mini mock of the header/button drawn from the local picks.
    private var preview: some View {
        let base = (isLight ? AppTheme.daylight : AppTheme.midnight).palette
        let accent2 = accent.brightnessAdjusted(isLight ? -0.08 : 0.14)
        let grad = LinearGradient(colors: [accent2, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        let onAccent: Color = accent.relativeLuminance > 0.5 ? Color(hex: "0b0f14") : .white
        return HStack(spacing: 12) {
            Circle().fill(grad).frame(width: 34, height: 34)
                .overlay(Image(systemName: "person.fill").font(.system(size: 13, weight: .semibold)).foregroundColor(onAccent))
            VStack(alignment: .leading, spacing: 3) {
                Text("Aa Bb Cc").font(.system(size: 13, weight: .semibold)).foregroundColor(base.text)
                Text("Accent preview").font(.system(size: 11)).foregroundColor(base.textDim)
            }
            Spacer()
            Text("Button").font(.system(size: 12, weight: .bold)).foregroundColor(onAccent)
                .padding(.horizontal, 14).frame(height: 34)
                .background(grad).clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .padding(14)
        .background(base.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(base.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
