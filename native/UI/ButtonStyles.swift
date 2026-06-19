import SwiftUI

// MARK: - Button styles

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct PrimaryButtonBody<Label: View>: View {
    let pressed: Bool
    let label: Label
    @ObservedObject private var themeStore = ThemeStore.shared

    init(pressed: Bool, @ViewBuilder label: () -> Label) {
        self.pressed = pressed
        self.label = label()
    }

    var body: some View {
        label
            .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.onAccent)
            .padding(.horizontal, 15).frame(minHeight: 44)
            .background(LinearGradient.accentFill.opacity(pressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.accentBorder, lineWidth: 1))
            .scaleEffect(pressed ? 0.97 : 1)
            .id(themeStore.theme.rawValue)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

struct SoftButton: ButtonStyle {
    var active = false
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(active: active, danger: danger, pressed: configuration.isPressed) { configuration.label }
    }
}

private struct SoftButtonBody<Label: View>: View {
    let active: Bool
    let danger: Bool
    let pressed: Bool
    let label: Label
    @ObservedObject private var themeStore = ThemeStore.shared

    init(active: Bool, danger: Bool, pressed: Bool, @ViewBuilder label: () -> Label) {
        self.active = active
        self.danger = danger
        self.pressed = pressed
        self.label = label()
    }

    var body: some View {
        let fg: Color = danger ? Theme.red : (active ? Theme.accent : Theme.text2)
        let stroke: Color = active ? Theme.accentBorder : Theme.border
        label
            .font(.system(size: 13, weight: .semibold)).foregroundColor(fg)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background((active ? Theme.accentSoft : (pressed ? Theme.surface2 : Theme.surface)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .scaleEffect(pressed ? 0.97 : 1)
            .id(themeStore.theme.rawValue)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

struct IconButton: ButtonStyle {
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(danger: danger, pressed: configuration.isPressed) { configuration.label }
    }
}

private struct IconButtonBody<L: View>: View {
    let danger: Bool
    let pressed: Bool
    @ViewBuilder var label: () -> L
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var hovering = false
    var body: some View {
        label()
            .font(.system(size: 14))
            .foregroundColor(pressed || hovering ? (danger ? .white : Theme.text) : Theme.textDim)
            .frame(width: 36, height: 36)
            .background((danger ? Theme.red : Theme.surface2).opacity(pressed ? 1 : (hovering ? (danger ? 0.85 : 1) : 0)))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .id(themeStore.theme.rawValue)
            .onHover { hovering = $0 }
    }
}
