import SwiftUI

// MARK: - Unlock method chooser

// Shown when the Locked pill is clicked and no default method is set. Lets the
// user pick Touch ID or PIN, and optionally remember the choice as the default.
struct UnlockChooserSheet: View {
    @ObservedObject var store: HostsStore
    var onTouchID: () -> Void
    var onPIN: () -> Void
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
        .padding(24).frame(width: 440).background(Theme.surface)
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

// Enter an existing PIN to unlock the edit session.
struct PinUnlockSheet: View {
    @ObservedObject var store: HostsStore
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
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Unlock") { submit() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 380).background(Theme.surface)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !pin.isEmpty else { return }
        if store.unlockWithPIN(pin) {
            dismiss()
        } else {
            error = "Incorrect PIN."
            pin = ""
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
                if isChange {
                    Button("Remove PIN") { store.removePIN(); dismiss() }
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
    return VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundColor(Theme.textDim)
        SecureField("••••", text: sanitized)
            .textFieldStyle(.plain)
            .focused(focused)
            .font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
            .padding(.horizontal, 12).frame(height: 44).background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onSubmit(onSubmit)
    }
}
