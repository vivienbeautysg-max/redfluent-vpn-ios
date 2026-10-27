import SwiftUI

/// Three quiet pages: the red dot comes down onto the line, one word each. No explanations.
struct OnboardingView: View {
    @Binding var done: Bool
    @State private var page = 0

    private let titles = ["Redfluent VPN", "Invite only", "Private"]

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            VStack(alignment: .leading, spacing: 0) {
                Wordmark()
                    .frame(height: 50)
                    .padding(.horizontal, Theme.gutter)
                Spacer(minLength: 0)
                LandingArt(landed: page == titles.count - 1, glowing: page == titles.count - 1,
                           height: compact ? 190 : 236, showsPower: false)
                Spacer(minLength: 0)
                TabView(selection: $page) {
                    ForEach(titles.indices, id: \.self) { i in
                        DotTitle(text: titles[i], size: compact ? 44 : 50, dot: .filled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.gutter)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: compact ? 70 : 80)
                HStack(spacing: 8) {
                    ForEach(titles.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Theme.Color.red : Theme.Color.rule)
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 14)
                .animation(.easeInOut(duration: 0.25), value: page)
                .accessibilityHidden(true)
                Button {
                    if page < titles.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        UserDefaults.standard.set(true, forKey: "rfv.onboardingDone")
                        withAnimation { done = true }
                    }
                } label: {
                    Text(page < titles.count - 1 ? "Next" : "Get started")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.gutter)
                .padding(.top, compact ? 22 : 34)
                .padding(.bottom, compact ? 16 : 28)
            }
        }
        .rfPage()
    }
}

#Preview {
    OnboardingView(done: .constant(false))
}
