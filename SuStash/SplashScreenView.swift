//
//  SplashScreenView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-17.
//

import Foundation
import SwiftUI

struct SplashScreenView: View {
    private enum Phase {
        case splash
        case onboarding
        case main
    }

    @AppStorage("hasSeenOnboarding", store: AppSettings.store) private var hasSeenOnboarding = false
    @State private var phase: Phase = .splash
    @State private var logoVisible = false

    var body: some View {
        switch phase {
        case .splash:
            splash
        case .onboarding:
            OnboardingView {
                hasSeenOnboarding = true
                withAnimation(.easeInOut(duration: 0.35)) { phase = .main }
            }
            .transition(.opacity)
        case .main:
            TabBarView()
                .transition(.opacity)
        }
    }

    private var splash: some View {
        ZStack {
            ThemedScreenBackground()

            VStack(spacing: 18) {
                Image("sustashlogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 30, y: 12)
                    .scaleEffect(logoVisible ? 1 : 0.82)
                    .opacity(logoVisible ? 1 : 0)

                Text("SuStash")
                    .font(AppTheme.titleFont(40))
                    .opacity(logoVisible ? 1 : 0)
                    .offset(y: logoVisible ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.28)) {
                logoVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    phase = hasSeenOnboarding ? .main : .onboarding
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
        .modelContainer(for: SavedItem.self, inMemory: true)
}
