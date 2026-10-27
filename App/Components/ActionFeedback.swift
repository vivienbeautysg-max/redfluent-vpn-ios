import SwiftUI
import UIKit

// What the user hears back after asking the server for something (create, save, delete, restore, log out,
// activate). One component for every such action: a banner pinned to the top of the screen, so the answer is
// seen whatever the scroll position and with the keyboard up.

struct ActionFeedback: Equatable, Identifiable {
    enum Kind { case success, failure }

    let id = UUID()
    let kind: Kind
    let text: String
    var detail: String?

    static func success(_ text: String, detail: String? = nil) -> ActionFeedback {
        ActionFeedback(kind: .success, text: text, detail: detail)
    }

    static func failure(_ text: String) -> ActionFeedback {
        ActionFeedback(kind: .failure, text: text)
    }

    /// Success goes after 2.5 s; a failure stays 6 s (a tap hides either).
    var seconds: Double { kind == .success ? 2.5 : 6 }
}

/// Success: Ink with the red dot. Failure: Red.
struct ActionBanner: View {
    let feedback: ActionFeedback

    private var failed: Bool { feedback.kind == .failure }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Circle().fill(Theme.Color.red).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.text)
                    .font(Theme.Font.text(14.5, .semibold))
                    .lineLimit(3)
                if let detail = feedback.detail {
                    Text(detail)
                        .font(Theme.Font.text(13, .medium))
                        .opacity(0.75)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(failed ? Theme.Color.onRed : Theme.Color.paper)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(failed ? Theme.Color.red : Theme.Color.ink)
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Shows `feedback` as a banner over the top of this view (`topInset` below its top edge), with the success or
    /// error haptic and a VoiceOver announcement. Put it on the part of the page under the pinned bar.
    func actionBanner(_ feedback: Binding<ActionFeedback?>, topInset: CGFloat = 6) -> some View {
        modifier(ActionBannerHost(feedback: feedback, topInset: topInset))
    }
}

private struct ActionBannerHost: ViewModifier {
    @Binding var feedback: ActionFeedback?
    let topInset: CGFloat
    @Environment(\.rfReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    if let shown = feedback {
                        ActionBanner(feedback: shown)
                            .padding(.horizontal, 16)
                            .padding(.top, topInset)
                            .onTapGesture { feedback = nil }
                            .id(shown.id)
                            .transition(.asymmetric(
                                insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -10)),
                                removal: .opacity.animation(Motion.bannerOut)))
                    }
                }
                .animation(reduceMotion ? Motion.fade : Motion.bannerIn, value: feedback?.id)
            }
            .onChange(of: feedback?.id) { _, id in
                guard id != nil, let shown = feedback else { return }
                if shown.kind == .success { Haptics.success() } else { Haptics.failure() }
                AccessibilityNotification.Announcement(shown.text).post()
            }
            .task(id: feedback?.id) {
                guard let shown = feedback else { return }
                try? await Task.sleep(for: .seconds(shown.seconds))
                if feedback?.id == shown.id { feedback = nil }
            }
    }
}

/// Before any save or create reads its fields: end editing. UIKit commits the text the keyboard is still
/// composing (marked text, e.g. a pinyin "p" not yet turned into a character) into the field and its binding,
/// so what is saved is exactly what the user sees; the keyboard goes away so the answer is in view.
@MainActor
enum EditCommit {
    static func endEditing() async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        await Task.yield()
    }
}
