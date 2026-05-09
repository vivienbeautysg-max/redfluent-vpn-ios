import SwiftUI

struct OnboardingView: View {
    @Binding var done: Bool
    @State private var page = 0

    private let slides: [Slide] = [
        Slide(
            symbol: "paperplane.fill",
            title: "RedFluent VPN",
            body: "A private secure tunnel built for trusted devices. Not a public service."
        ),
        Slide(
            symbol: "checkmark.shield.fill",
            title: "Invite only",
            body: "Each device gets its own revocable profile. No public signup, no advertising."
        ),
        Slide(
            symbol: "lock.fill",
            title: "Privacy first",
            body: "Your traffic is encrypted between this device and RedFluent infrastructure. We do not sell data."
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Color.brandPrimary, Theme.Color.brandSecondary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        slideView(slide).tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < slides.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        UserDefaults.standard.set(true, forKey: "rfv.onboardingDone")
                        withAnimation { done = true }
                    }
                } label: {
                    Text(page < slides.count - 1 ? "Next" : "Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(Theme.Color.textOnBrand)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 180, height: 180)
                Image(systemName: slide.symbol)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Theme.Color.textOnBrand)
            }
            Text(slide.title)
                .font(Theme.Font.displayLarge)
                .foregroundStyle(Theme.Color.textOnBrand)
            Text(slide.body)
                .font(Theme.Font.bodyLarge)
                .foregroundStyle(Theme.Color.textOnBrand.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            Spacer()
        }
    }

    private struct Slide {
        let symbol: String
        let title: String
        let body: String
    }
}

#Preview {
    OnboardingView(done: .constant(false))
}
