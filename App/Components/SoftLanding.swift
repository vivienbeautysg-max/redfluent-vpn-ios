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
        .touchTarget(width: 36, height: 36)
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
        .frame(height: Theme.barHeight)
    }
}

extension View {
    /// The scrolling part under a pinned BarRow: content passing under the bar fades out over 12 pt instead of
    /// being cut off by a hard edge.
    func underPinnedBar() -> some View {
        overlay(alignment: .top) {
            LinearGradient(colors: [Theme.Color.paper, Theme.Color.paper.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
                .allowsHitTesting(false)
        }
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
                .touchTarget(width: 30, height: 20)
        }
        .buttonStyle(PressStyle())
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
            .touchTarget(height: 20)
        }
        .buttonStyle(PressStyle())
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
            .background(Capsule().fill(Theme.Color.red.opacity(enabled ? 1 : 0.4)))
            .contentShape(Capsule())
            .pressEffect(configuration.isPressed && enabled)
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
            .touchTarget(height: 34)
            .pressEffect(configuration.isPressed)
    }
}

/// Choice between a few options: an outlined capsule with the chosen part filled in Ink. The filled pill slides to
/// the new option on a spring (Reduce Motion: it fades over instead).
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var enabled = true
    @Namespace private var pill
    @Environment(\.rfReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    guard !on else { return }
                    Haptics.select()
                    withAnimation(reduceMotion ? Motion.fade : Motion.slide) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(Theme.Font.text(14, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.Color.paper : Theme.Color.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background { fill(on) }
                        .touchTarget(height: 32)
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(Theme.Color.rule, lineWidth: 1))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    @ViewBuilder
    private func fill(_ on: Bool) -> some View {
        if reduceMotion {
            Capsule().fill(Theme.Color.ink).opacity(on ? 1 : 0)
        } else if on {
            Capsule().fill(Theme.Color.ink).matchedGeometryEffect(id: "pill", in: pill)
        }
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
                .foregroundStyle(Theme.Color.ink)
                .rollingNumber(value)
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
                .touchTarget(width: 32, height: 32)
        }
        .buttonStyle(PressStyle())
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
    @Environment(\.rfReduceMotion) private var reduceMotion

    private var problem: QuotaInput.Problem? {
        if case .failure(let problem) = QuotaInput.parse(text) { return problem }
        return nil
    }

    /// While typing, the keyboard covers the quick values row, so what is wrong shows in place of the label (the row
    /// the system keeps above the keyboard); otherwise it sits at the end of the quick values. A field emptied to
    /// type a new figure is not flagged while it is being typed in.
    private var rowProblem: String? {
        guard focused.wrappedValue, let problem, problem != .empty else { return nil }
        return problem.message
    }
    private var chipsProblem: String? { focused.wrappedValue ? nil : problem?.message }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    if let rowProblem {
                        problemLine(rowProblem)
                    } else {
                        Text("Monthly limit")
                            .font(Theme.Font.text(15, .medium))
                            .foregroundStyle(Theme.Color.ink)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? Motion.fade : .easeOut(duration: 0.2), value: rowProblem)
                Spacer(minLength: 8)
                // While typing, the field shows its own text. Otherwise the same figure is drawn over it as text, so
                // a quick value rolls in; the field underneath still takes the tap.
                TextField("", text: $text, prompt: Text(focused.wrappedValue ? "200" : "").foregroundStyle(Theme.Color.stone))
                    .font(Theme.Font.serif(22))
                    .foregroundStyle(focused.wrappedValue ? Theme.Color.ink : Color.clear)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .focused(focused)
                    .frame(maxWidth: 110)
                    .overlay(alignment: .trailing) {
                        if !focused.wrappedValue {
                            Text(text.isEmpty ? "200" : text)
                                .font(Theme.Font.serif(22))
                                .foregroundStyle(text.isEmpty ? Theme.Color.stone : Theme.Color.ink)
                                .lineLimit(1)
                                .rollingNumber(text)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("Monthly limit in GB")
                Text("GB")
                    .font(Theme.Font.text(14, .medium))
                    .foregroundStyle(Theme.Color.stone)
            }
            HStack(spacing: 8) {
                ForEach(QuotaInput.presets, id: \.self) { gb in
                    let on = QuotaInput.parse(text) == .success(gb)
                    Button {
                        pick(gb)
                    } label: {
                        Text("\(gb)")
                            .font(Theme.Font.text(14, on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.Color.paper : Theme.Color.ink)
                            .frame(minWidth: 52, minHeight: 32)
                            .background(Capsule().fill(Theme.Color.ink).opacity(on ? 1 : 0))
                            .overlay(Capsule().strokeBorder(Theme.Color.rule, lineWidth: 1).opacity(on ? 0 : 1))
                            .animation(Motion.fill, value: on)
                            .touchTarget(height: 32)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(gb) GB")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer(minLength: 0)
                ZStack(alignment: .trailing) {
                    if let chipsProblem {
                        problemLine(chipsProblem)
                    }
                }
                .animation(reduceMotion ? Motion.fade : .easeOut(duration: 0.2), value: chipsProblem)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rule() }
    }

    /// What is wrong, in red: fades in rising 4 pt (Reduce Motion: fades), leaves in 150 ms.
    private func problemLine(_ message: String) -> some View {
        Text(message)
            .font(Theme.Font.text(12.5, .medium))
            .foregroundStyle(Theme.Color.red)
            .lineLimit(1)
            .fixedSize()
            .id(message)
            .transition(.asymmetric(
                insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)),
                removal: .opacity.animation(Motion.bannerOut)))
    }

    /// A quick value is a complete answer: the keyboard goes, then the figure rolls to it.
    private func pick(_ gb: Int) {
        guard QuotaInput.parse(text) != .success(gb) else { return }
        Haptics.select()
        if focused.wrappedValue {
            focused.wrappedValue = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { text = String(gb) }
        } else {
            text = String(gb)
        }
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
                    Picker("Access", selection: presetBinding) {
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
                    .touchTarget(height: 20)
                }
                .menuStyle(.button)
                .buttonStyle(PressStyle())
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

    /// A different Access choice: the selection tick, and the Days row (Custom) fades in instead of popping.
    private var presetBinding: Binding<AccessPreset> {
        Binding(get: { access.preset }, set: { preset in
            guard preset != access.preset else { return }
            Haptics.select()
            withAnimation(Motion.fade) { access.preset = preset }
        })
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
/// straight line with a soft shadow. `pulsing` (connecting / disconnecting): the glow and a ring breathe around the
/// hovering dot. Drawn on the design's 390 x 236 grid, scaled to `height`.
///
/// Motion: landing is a soft spring that carries the dip with it and the glow blooms in over 400 ms; lifting off
/// (disconnect) takes 250 ms. Held down (PowerPressStyle), the dot alone shrinks to 0.94. Reduce Motion: nothing
/// travels or grows; the two resting states cross-fade and the breathing is a fade.
struct LandingArt: View {
    var landed: Bool
    var glowing: Bool = false
    var pulsing: Bool = false
    var height: CGFloat = 236
    var showsPower = true

    @Environment(\.rfPressed) private var pressed
    @Environment(\.rfReduceMotion) private var reduceMotion

    private var k: CGFloat { height / 236 }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            ZStack {
                LandingGlow(k: k)
                    .scaleEffect(glowing || reduceMotion ? 1 : 0.6)
                    .opacity(glowing ? 1 : 0)
                    .position(x: cx, y: 116 * k)
                    .animation(glowing ? .easeOut(duration: 0.4) : .easeIn(duration: 0.25), value: glowing)
                if pulsing {
                    Breathing(k: k, reduceMotion: reduceMotion)
                        .position(x: cx, y: dotY(landed: landed))
                        .transition(.opacity)
                }
                if reduceMotion {
                    scene(landed: false, cx: cx).opacity(landed ? 0 : 1)
                    scene(landed: true, cx: cx).opacity(landed ? 1 : 0)
                } else {
                    scene(landed: landed, cx: cx)
                }
            }
        }
        .frame(height: height)
        .animation(landing, value: landed)
        .animation(Motion.fade, value: pulsing)
    }

    private var landing: Animation {
        if reduceMotion { return .easeInOut(duration: 0.25) }
        return landed ? .spring(response: 0.55, dampingFraction: 0.7) : .easeInOut(duration: 0.25)
    }

    private func dotY(landed: Bool) -> CGFloat { (landed ? 116 : 62) * k }

    @ViewBuilder
    private func scene(landed: Bool, cx: CGFloat) -> some View {
        // The soft shadow under the hovering dot: blurred once, only its opacity changes.
        Ellipse()
            .fill(Theme.Color.ink.opacity(0.18))
            .frame(width: 88 * k, height: 10 * k)
            .blur(radius: 5 * k)
            .opacity(landed ? 0 : 1)
            .position(x: cx, y: 136 * k)
        DipLine(depth: landed ? 1 : 0, lineY: 141.7 * k, scale: k)
            .stroke(Theme.Color.ink, style: StrokeStyle(lineWidth: 8 * k, lineCap: .round))
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
            .scaleEffect(pressed && !reduceMotion ? Motion.powerScale : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.press, value: pressed)
            .position(x: cx, y: dotY(landed: landed))
    }
}

/// The red glow, rendered once into its own layer (drawingGroup), so scaling and fading it costs no redraw.
private struct LandingGlow: View {
    let k: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.Color.glow, Theme.Color.glow.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: 112 * k))
            .frame(width: 224 * k, height: 224 * k)
            .drawingGroup()
    }
}

/// Connecting: the glow and a thin ring around the dot breathe in and out, one breath every 1.2 s (0.6 s each way,
/// ease in-out). Reduce Motion: the glow only fades, it does not grow; no ring.
private struct Breathing: View {
    let k: CGFloat
    let reduceMotion: Bool

    var body: some View {
        PhaseAnimator([false, true]) { inhale in
            ZStack {
                LandingGlow(k: k)
                    .scaleEffect(reduceMotion ? 0.8 : (inhale ? 0.86 : 0.7))
                    .opacity(inhale ? 0.95 : 0.35)
                if !reduceMotion {
                    Circle()
                        .strokeBorder(Theme.Color.red.opacity(0.45), lineWidth: 2)
                        .frame(width: 108 * k, height: 108 * k)
                        .scaleEffect(inhale ? 1.2 : 1.04)
                        .opacity(inhale ? 0.7 : 0.15)
                }
            }
        } animation: { _ in
            .easeInOut(duration: 0.6)
        }
        .allowsHitTesting(false)
    }
}
