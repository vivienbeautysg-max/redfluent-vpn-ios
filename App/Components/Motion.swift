import SwiftUI
import UIKit
#if DEBUG
import os
#endif

// Motion and touch feel shared by every screen: press feedback, haptics, entrances, the theme cross-fade, edge
// swipe back, and the Reduce Motion switch all of them follow. Only transform and opacity are animated, except
// the line's dip (a small path) and the title's 4 pt blur.

enum Motion {
    /// Press: quick, a little give; a spring, so a release mid-press turns round from where it is.
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let pressScale: CGFloat = 0.96
    static let powerScale: CGFloat = 0.94
    /// The segmented pill sliding to the new option.
    static let slide = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// A chip's fill.
    static let fill = Animation.easeOut(duration: 0.15)
    /// Numbers rolling to a new value.
    static let numbers = Animation.smooth(duration: 0.35)
    /// Banners: in on a soft spring, out in 150 ms.
    static let bannerIn = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let bannerOut = Animation.easeIn(duration: 0.15)
    static let fade = Animation.easeInOut(duration: 0.2)
    /// Smallest touch target (Apple HIG).
    static let minTouch: CGFloat = 44

    #if DEBUG
    /// `-RFVReduceMotion`: behave as if Reduce Motion were on (recordings and checks on the simulator).
    static let forcedReduce = ProcessInfo.processInfo.arguments.contains("-RFVReduceMotion")
    #else
    static let forcedReduce = false
    #endif
}

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Reduce Motion as the app applies it: movement, scale and stagger become plain fades. Haptics stay.
    var rfReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}

/// Reads the system setting once at the root (and again in each sheet) and hands it down as `rfReduceMotion`.
struct MotionEnvironment: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        content.environment(\.rfReduceMotion, systemReduceMotion || Motion.forcedReduce)
    }
}

/// The app's haptics. Generators are made once and prepared ahead (on appear and on touch-down), so the first
/// tap is not late.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notice = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func prepare() {
        light.prepare()
        soft.prepare()
        notice.prepare()
        selection.prepare()
    }

    /// Power button pressed.
    static func tap() { light.impactOccurred(); light.prepare(); log("light") }
    /// Connected; an action the server accepted.
    static func success() { notice.notificationOccurred(.success); notice.prepare(); log("success") }
    /// Connect failed; an action the server refused.
    static func failure() { notice.notificationOccurred(.error); notice.prepare(); log("error") }
    /// Disconnected.
    static func off() { soft.impactOccurred(); soft.prepare(); log("soft") }
    /// A different option chosen (segmented, chip, theme, region, access).
    static func select() { selection.selectionChanged(); selection.prepare(); log("selection") }

    #if DEBUG
    private static let logger = Logger(subsystem: "com.redfluent.vpn", category: "haptics")
    /// One line per haptic, so a simulator run (which cannot feel them) shows when each one fired.
    private static func log(_ kind: String) { logger.notice("RFVHAPTIC \(kind, privacy: .public)") }
    #else
    private static func log(_ kind: String) {}
    #endif
}

// MARK: - Press feedback

private struct PressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The power button is held down (set by PowerPressStyle for the art inside it).
    var rfPressed: Bool {
        get { self[PressedKey.self] }
        set { self[PressedKey.self] = newValue }
    }
}

/// Shrinks a pressed control on the press spring; Reduce Motion: dims it instead. Prepares the haptics on touch-down.
struct PressEffect: ViewModifier {
    let pressed: Bool
    var scale: CGFloat = Motion.pressScale
    @Environment(\.rfReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(pressed && reduceMotion ? 0.6 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.press, value: pressed)
            .onChange(of: pressed) { _, down in if down { Haptics.prepare() } }
    }
}

extension View {
    func pressEffect(_ pressed: Bool, scale: CGFloat = Motion.pressScale) -> some View {
        modifier(PressEffect(pressed: pressed, scale: scale))
    }
}

/// Every tappable control that is not a list row (buttons, chips, segments, icons, links, menus): 0.96 while
/// pressed, no system grey flash.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = Motion.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.pressEffect(configuration.isPressed, scale: scale)
    }
}

/// List rows (people, devices, Recently Deleted, the action rows): a soft highlight behind the full-width row that
/// comes in fast (80 ms) and leaves slower (200 ms). A row does not shrink.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Theme.Color.soft
                    .padding(.horizontal, -Theme.gutter)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .easeOut(duration: 0.2),
                               value: configuration.isPressed)
            }
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.prepare() } }
    }
}

/// The power button: tells the art it is held, and the art shrinks only the dot (0.94); the line stays put.
struct PowerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.rfPressed, configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.prepare() } }
    }
}

extension View {
    /// Grows the touch target to at least 44 x 44 pt around a control drawn smaller (`width` x `height`), without
    /// moving anything: the extra area is padding that is taken back out of the layout. `width` nil = wide enough.
    func touchTarget(width: CGFloat? = nil, height: CGFloat) -> some View {
        let dx = width.map { max(0, (Motion.minTouch - $0) / 2) } ?? 0
        let dy = max(0, (Motion.minTouch - height) / 2)
        return padding(.horizontal, dx)
            .padding(.vertical, dy)
            .contentShape(Rectangle())
            .padding(.horizontal, -dx)
            .padding(.vertical, -dy)
    }
}

// MARK: - Content on screen

/// Content arriving on a screen: fades in and rises 8 pt, block after block (40 ms apart, at most 6 steps).
/// Reduce Motion: a plain fade, all at once. Once per life of the view (not again on the way back from a push).
struct Entrance: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.rfReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                let delay = reduceMotion ? 0 : Double(min(max(order, 0), 5)) * 0.04
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.4).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func entrance(_ order: Int) -> some View { modifier(Entrance(order: order)) }

    /// Figures that change in place (speed, ping, GB, timer, quota, counts): tabular digits, so nothing shifts
    /// sideways, and the new value rolls in. Reduce Motion: a cross-fade.
    func rollingNumber<V: Equatable>(_ value: V) -> some View { modifier(RollingNumber(value: value)) }
}

private struct RollingNumber<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.rfReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? Motion.fade : Motion.numbers, value: value)
    }
}

/// Title swap ("Disconnected." -> "Connecting."): the new title fades in rising 4 pt out of a slight blur, the old
/// one fades out. Reduce Motion: a plain cross-fade.
struct SwapEffect: ViewModifier {
    var rise: CGFloat
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: rise).opacity(opacity)
    }
}

extension AnyTransition {
    static let titleSwap: AnyTransition = .asymmetric(
        insertion: .modifier(active: SwapEffect(rise: 4, blur: 4, opacity: 0), identity: SwapEffect(rise: 0, blur: 0, opacity: 1)),
        removal: .modifier(active: SwapEffect(rise: -2, blur: 3, opacity: 0), identity: SwapEffect(rise: 0, blur: 0, opacity: 1)))

    /// A line that comes and goes (notice, error): fades in dropping 6 pt into place; leaves in 150 ms.
    static let notice: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .offset(y: -6)),
        removal: .opacity.animation(Motion.bannerOut))
}

// MARK: - Theme

/// Light / dark: the new appearance is applied under a snapshot of the screen that then fades out over 250 ms, so the
/// whole UI (sheets included) cross-fades from the old colours to the new ones with no white or black frame.
@MainActor
enum ThemeFade {
    static func apply(_ change: () -> Void) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window, let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            change()
            return
        }
        snapshot.frame = window.bounds
        snapshot.isUserInteractionEnabled = false
        window.addSubview(snapshot)
        change()
        // The short delay lets SwiftUI draw the new colours underneath before the old picture starts to go.
        UIView.animate(withDuration: 0.25, delay: 0.05, options: [.curveEaseInOut]) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }
}

// MARK: - Edge swipe back

/// MAX's standing rule: on every pushed screen, a swipe from the left edge goes back. The app hides the navigation bar
/// (its pages draw their own), and with the bar hidden UIKit's own delegate stops the back swipe from beginning. This
/// takes over as the delegate of the edge swipe (and, from iOS 26, of the swipe back from anywhere in the content):
/// either may begin whenever there is a page to go back to; the content one only for a mostly sideways move right.
struct EdgeSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) { controller.attach() }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        private var recognizers: [UIGestureRecognizer] {
            guard let nav = navigationController else { return [] }
            var list = [nav.interactivePopGestureRecognizer].compactMap { $0 }
            if #available(iOS 26.0, *), let content = nav.interactiveContentPopGestureRecognizer {
                list.append(content)
            }
            return list
        }

        func attach() {
            for recognizer in recognizers where recognizer.delegate !== self {
                recognizer.isEnabled = true
                recognizer.delegate = self
            }
        }

        private func isEdge(_ g: UIGestureRecognizer) -> Bool {
            g === navigationController?.interactivePopGestureRecognizer
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            var ok = (navigationController?.viewControllers.count ?? 0) > 1
            if ok, !isEdge(g), let pan = g as? UIPanGestureRecognizer {
                let v = pan.velocity(in: pan.view)
                ok = v.x > 0 && abs(v.x) > abs(v.y) * 1.5
            }
            #if DEBUG
            Logger(subsystem: "com.redfluent.vpn", category: "nav")
                .notice("RFVSWIPE shouldBegin \(self.isEdge(g) ? "edge" : "content") -> \(ok)")
            #endif
            return ok
        }

        /// Other gestures on the page wait for the edge swipe to fail, as under UIKit's own delegate.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            isEdge(g)
        }

        /// A drag that starts in a text field moves its cursor or selection; it never starts the swipe from the content.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if isEdge(g) { return true }
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView { return false }
                view = v.superview
            }
            return true
        }
    }
}

extension View {
    /// On the root and on every pushed page of a NavigationStack whose bar is hidden.
    func edgeSwipeBack() -> some View {
        background(EdgeSwipeBack().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
