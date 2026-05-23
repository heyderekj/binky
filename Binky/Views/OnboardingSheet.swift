import SwiftUI

/// First-launch onboarding: three slides explaining the Calm Inbox philosophy.
/// Shown once via `@AppStorage("binky.onboarding.v2.completed")`.
struct OnboardingSheet: View {
    @AppStorage("binky.onboarding.v2.completed") private var completed = false
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                slide1.tag(0)
                slide2.tag(1)
                slide3.tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(minHeight: 320)

            Divider()

            HStack {
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                        .buttonStyle(.borderless)
                }
                Spacer()
                if page < 2 {
                    Button("Next") { withAnimation { page += 1 } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get started") {
                        completed = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Slides

    private var slide1: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Calm Inbox")
                .font(.title.bold())
            Text("Binky watches your folders and suggests where files should go — but never moves anything without your say-so.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(30)
    }

    private var slide2: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("You decide")
                .font(.title.bold())
            Text("Each suggestion shows where a file would go and why. Tap Apply to move it, Skip to defer, or Reject to never see it again.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(30)
    }

    private var slide3: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Trust the trail")
                .font(.title.bold())
            Text("Every decision is remembered. Over time, Binky learns what you keep and what you toss — and gets quieter.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(30)
    }
}
