//
//  OnboardingView.swift
//  SuStash
//
//  First-run explainer. The share extension is the whole product and iOS
//  never teaches it — these three pages do.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                savePage.tag(1)
                smartPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pageCount - 1 {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pageCount - 1 ? "Continue" : "Start Stashing")
                    .font(AppTheme.headingFont(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Button("Skip", action: onFinish)
                .font(AppTheme.captionFont(14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
                .opacity(page < pageCount - 1 ? 1 : 0)
        }
        .background(ThemedScreenBackground())
    }

    private var welcomePage: some View {
        OnboardingPage(
            art: {
                Image("sustashlogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 28, y: 10)
            },
            title: "Your Links.\nOne Place",
            subtitle: "Videos, articles, recipes, products, GIFs — save anything from anywhere, and actually find it again."
        )
    }

    private var savePage: some View {
        OnboardingPage(
            art: {
                VStack(alignment: .leading, spacing: 14) {
                    onboardingStep(number: 1, icon: "square.and.arrow.up", text: "Tap Share in any app")
                    onboardingStep(number: 2, icon: "bookmark.fill", text: "Choose SuStash")
                    onboardingStep(number: 3, icon: "wand.and.stars", text: "Auto files it for you")
                }
                .padding(22)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            },
            title: "Save from anywhere",
            subtitle: "If SuStash isn't in your share sheet yet: scroll the app row right → More → Edit → add SuStash."
        )
    }

    private var smartPage: some View {
        OnboardingPage(
            art: {
                VStack(alignment: .leading, spacing: 14) {
                    onboardingFeature(icon: "sparkles", text: "Links sort themselves into collections")
                    onboardingFeature(icon: "magnifyingglass", text: "Search by meaning, not just words")
                    onboardingFeature(icon: "arrow.counterclockwise", text: "Rediscover what you saved and forgot")
                }
                .padding(22)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            },
            title: "It learns you",
            subtitle: "Everything runs on your device. No accounts, no tracking — your stash is yours."
        )
    }

    private func onboardingStep(number: Int, icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(AppTheme.headingFont(15))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AppTheme.accent.gradient, in: Circle())
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 26)
            Text(text)
                .font(AppTheme.bodyFont(16))
        }
    }

    private func onboardingFeature(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30)
            Text(text)
                .font(AppTheme.bodyFont(16))
        }
    }
}

private struct OnboardingPage<Art: View>: View {
    @ViewBuilder var art: () -> Art
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            art()
            VStack(spacing: 12) {
                Text(title)
                    .font(AppTheme.titleFont(32))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppTheme.bodyFont(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
