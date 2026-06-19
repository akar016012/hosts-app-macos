import SwiftUI

// MARK: - Button styles

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 15).frame(minHeight: 44)
            .background(LinearGradient.accentFill.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftButton: ButtonStyle {
    var active = false
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        let fg: Color = danger ? Theme.red : (active ? Theme.accent : Theme.text2)
        let stroke: Color = active ? Theme.accentBorder : Theme.border
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundColor(fg)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background((active ? Theme.accentSoft : (configuration.isPressed ? Theme.surface2 : Theme.surface)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    @State private var hovering = false
    var body: some View {
        label()
            .font(.system(size: 14))
            .foregroundColor(pressed || hovering ? (danger ? .white : Theme.text) : Theme.textDim)
            .frame(width: 36, height: 36)
            .background((danger ? Theme.red : Theme.surface2).opacity(pressed ? 1 : (hovering ? (danger ? 0.85 : 1) : 0)))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .onHover { hovering = $0 }
    }
}
