import AppKit
import SwiftUI

/// Haul's colour tokens and the small custom controls built from them.
enum Theme {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }

    static let win = dynamic(rgb(0xFFFFFF), rgb(0x1E1E21))
    static let side = dynamic(rgb(0xF2F2F5), rgb(0x29292D))
    static let page = dynamic(rgb(0xFFFFFF), rgb(0x3A3A3F))
    static let text = dynamic(rgb(0x1D1D1F), rgb(0xF5F5F7))
    static let text2 = dynamic(rgb(0, 0.56), rgb(0xFFFFFF, 0.6))
    static let text3 = dynamic(rgb(0, 0.34), rgb(0xFFFFFF, 0.34))
    static let sep = dynamic(rgb(0, 0.08), rgb(0xFFFFFF, 0.08))
    static let hover = dynamic(rgb(0, 0.045), rgb(0xFFFFFF, 0.06))
    static let selg = dynamic(rgb(0, 0.075), rgb(0xFFFFFF, 0.1))
    static let field = dynamic(rgb(0, 0.05), rgb(0xFFFFFF, 0.08))
    static let track = dynamic(rgb(0, 0.09), rgb(0xFFFFFF, 0.14))
    static let ctl = dynamic(rgb(0xFFFFFF), rgb(0xFFFFFF, 0.09))
    static let ctlB = dynamic(rgb(0, 0.1), rgb(0xFFFFFF, 0.14))
    static let group = dynamic(rgb(0, 0.035), rgb(0xFFFFFF, 0.045))
    static let ctlRing = dynamic(rgb(0, 0.1), rgb(0xFFFFFF, 0.12))
    static let ctlShadow = dynamic(rgb(0, 0.08), rgb(0, 0.3))
    static let red = dynamic(rgb(0xE5372D), rgb(0xFF5147))
    static let green = dynamic(rgb(0x2A9D48), rgb(0x3CC760))
    static let orange = dynamic(rgb(0xE08A00), rgb(0xFFA31A))

    static var accent: Color { AppSettings.shared.accent.color }
}

extension View {
    /// `Theme.ctl` background with a hairline ring and a soft drop shadow.
    func controlChrome<S: InsettableShape>(_ shape: S, fill: Color = Theme.ctl) -> some View {
        background {
            shape.fill(fill)
                .shadow(color: Theme.ctlShadow, radius: 1.5, y: 1)
                .overlay(shape.strokeBorder(Theme.ctlRing, lineWidth: 0.5))
        }
    }

    func capsuleControl() -> some View { controlChrome(Capsule()) }
}

/// Plain button that dims slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Pill button: neutral (`Theme.ctl`) or filled with the accent colour.
struct PillButton: View {
    let title: String
    var prominent = false
    var height: CGFloat = 28
    var fontSize: CGFloat = 13
    var foreground: Color?
    var expand = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: prominent ? .medium : .regular))
                .foregroundStyle(foreground ?? (prominent ? .white : Theme.text))
                .padding(.horizontal, 16)
                .frame(maxWidth: expand ? .infinity : nil)
                .frame(height: height)
                .background { if prominent { Capsule().fill(Theme.accent) } }
                .modifier(ConditionalChrome(enabled: !prominent))
        }
        .buttonStyle(.pressable)
    }
}

private struct ConditionalChrome: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.capsuleControl() } else { content }
    }
}

/// 32×18 switch used in Settings.
struct DesignSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.track)
                .frame(width: 32, height: 18)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .frame(width: 16, height: 16)
                        .offset(x: isOn ? 15 : 1)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// Segmented control: `Theme.field` trough with the selected segment raised.
struct DesignSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var minWidth: CGFloat = 38

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .frame(minWidth: minWidth, minHeight: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5).fill(Theme.ctl)
                                    .shadow(color: Theme.ctlShadow, radius: 1.5, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.ctlRing, lineWidth: 0.5))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
        .fixedSize()
    }
}

struct DesignCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? Theme.accent : Theme.ctl)
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                        } else {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ctlB, lineWidth: 1)
                        }
                    }
                    .frame(width: 14, height: 14)
                Text(title)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Rounded `Theme.group` card whose rows are separated by hairlines.
struct DesignGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    row.overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Theme.sep).frame(height: 0.5) }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))
    }
}

/// Custom-drawn window controls, placed to fit the header; the system ones are hidden.
struct TrafficLights: View {
    let window: NSWindow?
    var canMinimize = true
    @Environment(\.appearsActive) private var appearsActive
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            light(Color(hex: 0xFF5F57), glyph: "xmark") { window?.performClose(nil) }
            if canMinimize {
                light(Color(hex: 0xFEBC2E), glyph: "minus") { window?.miniaturize(nil) }
                light(Color(hex: 0x28C840), glyph: "arrow.up.left.and.arrow.down.right") { window?.toggleFullScreen(nil) }
            } else {
                Circle().fill(Theme.track).frame(width: 12, height: 12)
                Circle().fill(Theme.track).frame(width: 12, height: 12)
            }
        }
        .onHover { hovering = $0 }
    }

    private func light(_ color: Color, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(appearsActive || hovering ? color : Theme.track)
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                .overlay {
                    if hovering {
                        Image(systemName: glyph)
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Hands back the hosting NSWindow and hides the standard window buttons.
///
/// AppKit restores parts of the title bar when a sheet is shown or the window changes
/// key state, so the configuration is re-applied on those events, not just once.
struct WindowConfigurator: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            configure(window)
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didEndSheetNotification, NSWindow.didBecomeMainNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.window else { return }
                        self.configure(window)
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.configure(window)
                self.onWindow?(window)
            }
        }

        func configure(_ window: NSWindow) {
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = true
            }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.onWindow = onWindow
    }
}

/// Transparent area that drags the window and zooms it on double-click, like a title bar.
struct WindowDragArea: View {
    let window: NSWindow?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .onTapGesture(count: 2) { window?.zoom(nil) }
    }
}
