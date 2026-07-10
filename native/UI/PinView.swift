// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import SwiftUI

// MARK: - Unlock method chooser

// Shown when the Locked pill is clicked and no default method is set. Lets the
// user pick Touch ID or PIN, and optionally remember the choice as the default.
struct UnlockChooserSheet: View {
    @ObservedObject var store: HostsStore
    var onTouchID: () -> Void
    var onPIN: () -> Void
    var onPassword: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var makeDefault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unlock edits").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            Text("Choose how to unlock Hosts for this session.")
                .font(.system(size: 12.5)).foregroundColor(Theme.textDim)

            HStack(spacing: 12) {
                optionCard(icon: "touchid", title: "Touch ID",
                           subtitle: store.touchIDAvailable ? "Use your fingerprint" : "Unavailable here",
                           enabled: store.touchIDAvailable) {
                    if makeDefault { store.defaultUnlock = .touchID }
                    dismiss(); onTouchID()
                }
                optionCard(icon: "number.square.fill", title: "PIN",
                           subtitle: store.pinSet ? "Enter your PIN" : "Set up a PIN",
                           enabled: true) {
                    if makeDefault { store.defaultUnlock = .pin }
                    dismiss(); onPIN()
                }
                optionCard(icon: "key.fill", title: "Password",
                           subtitle: "Your macOS login password",
                           enabled: true) {
                    if makeDefault { store.defaultUnlock = .password }
                    dismiss(); onPassword()
                }
            }

            Toggle(isOn: $makeDefault) {
                Text("Remember my choice — skip this next time")
                    .font(.system(size: 12.5)).foregroundColor(Theme.text2)
            }
            .tint(Theme.accent)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
            }
        }
        .padding(24).frame(width: 560).background(Theme.surface)
    }

    private func optionCard(icon: String, title: String, subtitle: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 30, weight: .medium)).foregroundColor(Theme.accent)
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                    Text(subtitle).font(.system(size: 11)).foregroundColor(Theme.textDim)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - PIN sheets

// Destructive confirmation shared by every "Remove PIN" affordance (setup sheet,
// profile menu, lock-pill context menu).
@MainActor
func confirmRemovePIN(store: HostsStore, then: (() -> Void)? = nil) {
    let alert = NSAlert()
    alert.messageText = "Remove PIN?"
    alert.informativeText = "You'll no longer be able to unlock edits with a PIN. Touch ID (where available) remains the other unlock method."
    alert.addButton(withTitle: "Remove")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    if alert.runModal() == .alertFirstButtonReturn {
        store.removePIN()
        then?()
    }
}

// Enter an existing PIN to unlock the edit session.
struct PinUnlockSheet: View {
    @ObservedObject var store: HostsStore
    // Runs after a successful forgot-PIN reset so the caller can chain the
    // setup sheet once this one has dismissed.
    var onReset: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "number.square.fill").font(.system(size: 18)).foregroundColor(Theme.accent)
                Text("Unlock with PIN").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            }
            Text("Enter your PIN to unlock edits for this session.")
                .font(.system(size: 12.5)).foregroundColor(Theme.textDim)

            pinField("PIN", text: $pin, focused: $focused) { submit() }

            if let error { Text(error).foregroundColor(Theme.red).font(.system(size: 13)) }

            HStack {
                Button("Forgot PIN?") { confirmReset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Unlock") { submit() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 380).background(Theme.surface)
        .onAppear { focused = true }
    }

    // Explains the recovery rule before authenticating: while locked, only
    // macOS authentication (login password, or Touch ID where available) can
    // reset the PIN. Cancelling any step changes nothing.
    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset your PIN?"
        alert.informativeText = "Hosts is locked, so to reset your PIN you need to authenticate with your macOS login password\(store.touchIDAvailable ? " or Touch ID" : ""). Your current PIN will be removed and you can set a new one."
        alert.addButton(withTitle: "Enter Password…")
        if store.touchIDAvailable { alert.addButton(withTitle: "Use Touch ID…") }
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if promptLoginPassword() { dismiss(); onReset() }
        case .alertSecondButtonReturn where store.touchIDAvailable:
            Task {
                if await store.resetForgottenPIN() {
                    dismiss()
                    onReset()
                }
            }
        default:
            break
        }
    }

    // Secure-field prompt for the macOS login password; loops on a wrong
    // password so a typo doesn't send the user back through the whole flow.
    private func promptLoginPassword() -> Bool {
        var failed = false
        while true {
            let alert = NSAlert()
            alert.messageText = "Enter your macOS password"
            alert.informativeText = failed
                ? "That password wasn't correct. Enter the login password for \"\(NSFullUserName())\" to reset your Hosts PIN."
                : "Enter the login password for \"\(NSFullUserName())\" to reset your Hosts PIN."
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            alert.addButton(withTitle: "Reset PIN")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            if store.resetForgottenPIN(loginPassword: field.stringValue) { return true }
            failed = true
        }
    }

    private func submit() {
        guard !pin.isEmpty else { return }
        switch store.unlockWithPIN(pin) {
        case .unlocked:
            dismiss()
        case .wrong(let message):
            error = message
            pin = ""
            focused = true
        case .locked(let message):
            error = message
            pin = ""
        }
    }
}

// Enter the macOS login password to unlock the edit session — the path for
// Macs without Touch ID when the PIN is forgotten or locked out.
struct PasswordUnlockSheet: View {
    @ObservedObject var store: HostsStore
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").font(.system(size: 18)).foregroundColor(Theme.accent)
                Text("Unlock with macOS Password").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            }
            Text("Enter the login password for \"\(NSFullUserName())\" to unlock edits for this session.")
                .font(.system(size: 12.5)).foregroundColor(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            secureField("MACOS PASSWORD", text: $password, focused: $focused) { submit() }

            if let error { Text(error).foregroundColor(Theme.red).font(.system(size: 13)) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Unlock") { submit() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 420).background(Theme.surface)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        if store.unlockWithLoginPassword(password) {
            dismiss()
        } else {
            error = "Incorrect password."
            password = ""
            focused = true
        }
    }
}

// Set, change, or remove the unlock PIN.
struct PinSetupSheet: View {
    @ObservedObject var store: HostsStore
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var confirm = ""
    @State private var error: String? = nil
    @FocusState private var pinFocused: Bool
    @FocusState private var confirmFocused: Bool

    private var isChange: Bool { store.pinSet }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isChange ? "Change PIN" : "Set up PIN")
                .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            Text("Use a \(PinStore.minLength)–\(PinStore.maxLength) digit PIN as an alternative to Touch ID for unlocking edits.")
                .font(.system(size: 12.5)).foregroundColor(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            pinField(isChange ? "NEW PIN" : "PIN", text: $pin, focused: $pinFocused) { confirmFocused = true }
            pinField("CONFIRM PIN", text: $confirm, focused: $confirmFocused) { save() }

            if let error { Text(error).foregroundColor(Theme.red).font(.system(size: 13)) }

            HStack {
                if isChange && store.sessionUnlocked {
                    Button("Remove PIN") { confirmRemovePIN(store: store) { dismiss() } }
                        .buttonStyle(SoftButton(danger: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button(isChange ? "Update" : "Save") { save() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 420).background(Theme.surface)
        .onAppear { pinFocused = true }
    }

    private func save() {
        if let reason = PinStore.validate(pin) { error = reason; return }
        guard pin == confirm else { error = "PINs don't match."; return }
        if let reason = store.setPIN(pin) { error = reason; return }
        dismiss()
    }
}

// Shared secure numeric field styled like the entry editor's fields.
private func pinField(_ label: String, text: Binding<String>,
                      focused: FocusState<Bool>.Binding,
                      onSubmit: @escaping () -> Void) -> some View {
    // Sanitize on write: keep digits only, cap at the max length.
    let sanitized = Binding(get: { text.wrappedValue },
                            set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(PinStore.maxLength)) })
    return secureField(label, text: sanitized, focused: focused, onSubmit: onSubmit)
}

// Free-form secure field with the same chrome as pinField (used for the macOS
// login password, which isn't digits-only).
private func secureField(_ label: String, text: Binding<String>,
                         focused: FocusState<Bool>.Binding,
                         onSubmit: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
        SecureField("••••", text: text)
            .textFieldStyle(.plain)
            .focused(focused)
            .font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
            .padding(.horizontal, 12).frame(height: 44).background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onSubmit(onSubmit)
    }
}
