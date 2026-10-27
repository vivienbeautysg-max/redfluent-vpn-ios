import SwiftUI

// Building blocks of the "01 Soft Landing" design, shared by every screen.

/// The brand mark: a line with a soft dip and the red dot resting on it (120 x 120 grid).
struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvas in
            let k = canvas.width / 120
            var line = Path()
            line.move(to: CGPoint(x: 14 * k, y: 72 * k))
            line.addLine(to: CGPoint(x: 32 * k, y: 72 * k))
            line.addCurve(to: CGPoint(x: 60 * k, y: 84.5 * k), control1: CGPoint(x: 43 * k, y: 72 * k), control2: CGPoint(x: 44 * k, y: 84.5 * k))
            line.addCurve(to: CGPoint(x: 88 * k, y: 72 * k), control1: CGPoint(x: 76 * k, y: 84.5 * k), control2: CGPoint(x: 77 * k, y: 72 * k))
            line.addLine(to: CGPoint(x: 106 * k, y: 72 * k))
            context.stroke(line, with: .color(Theme.Color.ink), style: StrokeStyle(lineWidth: 7 * k, lineCap: .round))
            let dot = Path(ellipseIn: CGRect(x: (60 - 23) * k, y: (58 - 23) * k, width: 46 * k, height: 46 * k))
            context.fill(dot, with: .color(Theme.Color.red))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Mark + "Redfluent" + small "VPN".
struct Wordmark: View {
    var markSize: CGFloat = 30
    var nameSize: CGFloat = 21

    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: markSize)
            Text("Redfluent")
                .font(Theme.Font.serif(nameSize))
                .tracking(-0.01 * nameSize)
                .foregroundStyle(Theme.Color.ink)
            Text("VPN")
                .font(Theme.Font.text(nameSize * 0.5, .semibold))
                .tracking(0.2 * nameSize * 0.5)
                .foregroundStyle(Theme.Color.stone)
                .padding(.top, 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Redfluent VPN")
    }
}

enum DotStyle { case filled, hollow, none }

/// A Fraunces title ending in the dot: "Connected." (filled red) / "Disconnected." (hollow).
struct DotTitle: View {
    let text: String
    var size: CGFloat = 50
    var dot: DotStyle = .filled
    var dotColor: Color = Theme.Color.red
    var lineLimit: Int? = 1

    var body: some View {
        if lineLimit == 1 { oneLine } else { wrapping }
    }

    /// Several lines: the dot is part of the text, so it follows the last word instead of the widest line.
    private var wrapping: some View {
        (Text(text).foregroundColor(Theme.Color.ink) + inlineDot)
            .font(Theme.Font.display(size))
            .tracking(-0.025 * size)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.6)
    }

    private var inlineDot: Text {
        guard dot != .none else { return Text("") }
        return Text("\u{202F}")   // narrow no-break space: the dot never ends up alone on a line
            + Text(Image(systemName: dot == .filled ? "circle.fill" : "circle"))
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundColor(dot == .filled ? dotColor : Theme.Color.stone)
    }

    private var oneLine: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.1) {
            Text(text)
                .font(Theme.Font.display(size))
                .tracking(-0.025 * size)
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.6)
            if dot != .none {
                Circle()
                    .fill(dot == .filled ? dotColor : .clear)
                    .overlay(Circle().strokeBorder(dot == .hollow ? Theme.Color.stone : .clear, lineWidth: max(1.5, size * 0.04)))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 1 pt hairline in Rule colour.
struct Rule: View {
    var body: some View {
        Rectangle().fill(Theme.Color.rule).frame(height: 1)
    }
}

/// The round "…" button the menus hang off.
struct MoreGlyph: View {
    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.Color.ink).frame(width: 3.4, height: 3.4) }
        }
        .frame(width: 36, height: 36)
        .overlay(Circle().strokeBorder(Theme.Color.rule, lineWidth: 1))
        .contentShape(Circle())
    }
}

/// Small uppercase section label ("DEVICES · 3").
struct SectionLabel: View {
    let text: String
    var body: some View { Text(text).rfLabelStyle() }
}

/// Outlined capsule tag: "DEDICATED" (red), "PAUSED" (stone).
struct Tag: View {
    let text: String
    var color: Color = Theme.Color.red

    var body: some View {
        Text(text)
            .font(Theme.Font.text(9.5, .semibold))
            .tracking(0.12 * 9.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(color, lineWidth: 1))
            .fixedSize()
    }
}

/// Top row of a sheet / pushed page: leading action, centred title, trailing action (46 pt).
struct BarRow<Leading: View, Trailing: View>: View {
    var title: String = ""
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.Font.text(16.5, .semibold))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            HStack {
                leading
                Spacer(minLength: 12)
                trailing
            }
        }
        .frame(height: 46)
    }
}

/// Text button in a bar: red, Archivo 16.5.
struct BarButton: View {
    let title: String
    var bold = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.text(16.5, bold ? .semibold : .medium))
                .foregroundStyle(enabled ? Theme.Color.red : Theme.Color.stone)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// "‹ People" back button.
struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                Text(title).font(Theme.Font.text(16.5, .medium))
            }
            .foregroundStyle(Theme.Color.red)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}

/// Red capsule button, full width.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.text(16, .semibold))
            .foregroundStyle(Theme.Color.onRed)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Theme.Color.red.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)))
    }
}

/// Outlined capsule button (Restore, Copy, Share).
struct OutlineButtonStyle: ButtonStyle {
    var color: Color = Theme.Color.red

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.text(14, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .overlay(Capsule().strokeBorder(color, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Choice between a few options: an outlined capsule with the chosen part filled in Ink.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var enabled = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(Theme.Font.text(14, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.Color.paper : Theme.Color.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(on ? Theme.Color.ink : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(Theme.Color.rule, lineWidth: 1))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// − n + for small whole numbers (device limit).
struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 14) {
            step("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
            Text("\(value)")
                .font(Theme.Font.serif(20))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.ink)
                .frame(minWidth: 28)
            step("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + 1) }
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Theme.Color.ink : Theme.Color.stone)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Theme.Color.rule, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }
}

/// A settings row: label on the left, control on the right, hairline below.
struct SettingRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(label)
                    .font(Theme.Font.text(15, .medium))
                    .foregroundStyle(Theme.Color.ink)
                    .fixedSize()
                Spacer(minLength: 8)
                control
            }
            .frame(minHeight: 52)
            Rule()
        }
    }
}

/// Plain text field in the theme (no box: the row's hairline is the edge).
struct ThemedField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var alignment: TextAlignment = .trailing
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.Color.stone))
            .font(mono ? Theme.Font.mono(15) : Theme.Font.text(15))
            .foregroundStyle(Theme.Color.ink)
            .multilineTextAlignment(alignment)
            .keyboardType(keyboard)
            .textInputAutocapitalization(mono ? .never : .words)
            .autocorrectionDisabled()
    }
}

/// Monthly quota input: any whole number 1–2000 plus the quick values; says what is wrong in one short line.
struct QuotaField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Monthly limit")
                    .font(Theme.Font.text(15, .medium))
                    .foregroundStyle(Theme.Color.ink)
                    .fixedSize()
                Spacer(minLength: 8)
                TextField("", text: $text, prompt: Text("200").foregroundStyle(Theme.Color.stone))
                    .font(Theme.Font.serif(22))
                    .foregroundStyle(Theme.Color.ink)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .focused(focused)
                    .frame(maxWidth: 110)
                    .accessibilityLabel("Monthly limit in GB")
                Text("GB")
                    .font(Theme.Font.text(14, .medium))
                    .foregroundStyle(Theme.Color.stone)
            }
            HStack(spacing: 8) {
                ForEach(QuotaInput.presets, id: \.self) { gb in
                    let on = QuotaInput.parse(text) == .success(gb)
                    Button {
                        text = String(gb)
                    } label: {
                        Text("\(gb)")
                            .font(Theme.Font.text(14, on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.Color.paper : Theme.Color.ink)
                            .frame(minWidth: 52, minHeight: 32)
                            .background(Capsule().fill(on ? Theme.Color.ink : .clear))
                            .overlay(Capsule().strokeBorder(on ? .clear : Theme.Color.rule, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(gb) GB")
                }
                Spacer(minLength: 0)
                if case .failure(let problem) = QuotaInput.parse(text) {
                    Text(problem.message)
                        .font(Theme.Font.text(12.5, .medium))
                        .foregroundStyle(Theme.Color.red)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rule() }
    }
}

/// Region and Access for an invite (Create and the person page). Region is a plain value when there is nothing
/// to choose between.
struct InviteAccessRows: View {
    @Binding var region: String
    @Binding var access: AccessChoice
    let regionOptions: [VPNRegion]
    var showsAccess: Bool = true
    var status: InviteStatus?

    var body: some View {
        SettingRow(label: "Region") {
            if regionOptions.count > 1 {
                SegmentedChoice(options: regionOptions.map { (value: $0.id, title: $0.name) }, selection: $region)
            } else {
                Text(regionOptions.first?.name ?? "Tokyo")
                    .font(Theme.Font.text(15))
                    .foregroundStyle(Theme.Color.stone)
            }
        }
        if showsAccess {
            SettingRow(label: "Access") {
                Menu {
                    Picker("Access", selection: $access.preset) {
                        ForEach(AccessPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(access.preset.label)
                            .font(Theme.Font.text(15, .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Color.ink)
                }
            }
            if access.preset == .custom {
                SettingRow(label: "Days") {
                    TextField("", value: $access.customDays, format: .number)
                        .font(Theme.Font.serif(20))
                        .foregroundStyle(Theme.Color.ink)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
            }
        }
        if let status {
            Text(status.text)
                .font(Theme.Font.text(12.5, .medium))
                .foregroundStyle(status.tone.color)
                .padding(.top, 8)
        }
    }
}

extension StatusTone {
    var color: Color {
        switch self {
        case .neutral: return Theme.Color.stone
        case .warning, .danger: return Theme.Color.red
        }
    }
}

// MARK: - The switch: a line, and the red dot that lands on it

/// The dip in the line under the dot. depth 0 = straight line, 1 = the dot's full weight.
struct DipLine: Shape {
    var depth: CGFloat
    var lineY: CGFloat
    var scale: CGFloat

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, y = lineY, k = scale, d = 34.7 * k * depth
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - 10, y: y))
        p.addLine(to: CGPoint(x: cx - 77.1 * k, y: y))
        p.addCurve(to: CGPoint(x: cx, y: y + d),
                   control1: CGPoint(x: cx - 48.9 * k, y: y), control2: CGPoint(x: cx - 43.7 * k, y: y + d))
        p.addCurve(to: CGPoint(x: cx + 77.1 * k, y: y),
                   control1: CGPoint(x: cx + 43.7 * k, y: y + d), control2: CGPoint(x: cx + 48.9 * k, y: y))
        p.addLine(to: CGPoint(x: rect.maxX + 10, y: y))
        return p
    }
}

/// The line + dot. `landed` (connected): the dot rests in the dip with a glow; otherwise it hovers above a
/// straight line with a soft shadow. Drawn on the design's 390 x 236 grid, scaled to `height`.
struct LandingArt: View {
    var landed: Bool
    var glowing: Bool = false
    var pulsing: Bool = false
    var height: CGFloat = 236
    var showsPower = true

    @State private var pulse = false

    private var k: CGFloat { height / 236 }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let dotY = (landed ? 116 : 62) * k
            ZStack {
                if glowing {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.Color.glow, Theme.Color.glow.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 112 * k))
                        .frame(width: 224 * k, height: 224 * k)
                        .position(x: cx, y: 116 * k)
                        .transition(.opacity)
                }
                Ellipse()
                    .fill(Theme.Color.ink.opacity(landed ? 0 : 0.18))
                    .frame(width: 88 * k, height: 10 * k)
                    .blur(radius: 5 * k)
                    .position(x: cx, y: 136 * k)
                DipLine(depth: landed ? 1 : 0, lineY: 141.7 * k, scale: k)
                    .stroke(Theme.Color.ink, style: StrokeStyle(lineWidth: 8 * k, lineCap: .round))
                if pulsing {
                    Circle()
                        .strokeBorder(Theme.Color.red.opacity(0.5), lineWidth: 2)
                        .frame(width: 108 * k, height: 108 * k)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 1)
                        .position(x: cx, y: dotY)
                        .onAppear { withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true } }
                        .onDisappear { pulse = false }
                }
                Circle()
                    .fill(Theme.Color.red)
                    .frame(width: 108 * k, height: 108 * k)
                    .overlay {
                        if showsPower {
                            Image(systemName: "power")
                                .font(.system(size: 34 * k, weight: .medium))
                                .foregroundStyle(Theme.Color.onRed)
                        }
                    }
                    .position(x: cx, y: dotY)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.62, dampingFraction: 0.62), value: landed)
        .animation(.easeInOut(duration: 0.4), value: glowing)
    }
}
