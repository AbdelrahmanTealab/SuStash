//
//  PaywallView.swift
//  SuStash
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProStore.shared
    @State private var purchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits
                    purchaseButtons
                    restoreButton
                    footnote
                }
                .padding(20)
            }
            .background(ThemedScreenBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.accent.gradient)
            Text("SuStash Pro")
                .font(AppTheme.titleFont(28))
            Text("Your stash, everywhere — and exactly your style.")
                .font(AppTheme.captionFont(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefit("wand.and.stars", "Smart Filing", "Learns how you organize and files new links your way — all on this device.")
            benefit("sparkles", "Smart Suggestions", "Rediscover surfaces saved links similar to what you actually open.")
            benefit("icloud.fill", "iCloud Sync", "Every link on all your devices, automatically.")
            benefit("paintpalette.fill", "Themes", "Cotton Candy, Cyberpunk, Retro, Neon — full palettes, fonts, and ambient backgrounds.")
            benefit("square.and.arrow.up.fill", "Export", "Your entire library as JSON, anytime.")
            benefit("heart.fill", "Support an indie", "SuStash is built by one person — Pro keeps it going.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTheme.headingFont(15))
                Text(detail)
                    .font(AppTheme.captionFont(13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var purchaseButtons: some View {
        if store.products.isEmpty {
            VStack(spacing: 8) {
                if store.didFinishLoadingProducts {
                    Text("Plans aren't available right now.\nCheck your connection and try again.")
                        .font(AppTheme.captionFont(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await store.loadProducts() }
                    }
                    .font(AppTheme.headingFont(14))
                } else {
                    ProgressView()
                    Text("Loading plans…")
                        .font(AppTheme.captionFont(13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        } else {
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    Button {
                        purchase(product)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(planName(for: product))
                                    .font(AppTheme.headingFont(15))
                                if let badge = planBadge(for: product) {
                                    Text(badge)
                                        .font(AppTheme.captionFont(12))
                                        .opacity(0.85)
                                }
                            }
                            Spacer()
                            Text(product.displayPrice)
                                .font(AppTheme.headingFont(16))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(
                            product.id == ProStore.yearlyID
                                ? AnyShapeStyle(AppTheme.accent.gradient)
                                : AnyShapeStyle(AppTheme.card),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(product.id == ProStore.yearlyID ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(purchasing)

            if let error = store.lastPurchaseError {
                Text(error)
                    .font(AppTheme.captionFont(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task {
                await store.restorePurchases()
                if store.isPro { dismiss() }
            }
        }
        .font(AppTheme.captionFont(14))
    }

    private static let privacyPolicyURL = "https://abdelrahmantealab.github.io/sustash-legal/PRIVACY"
    private static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    private var footnote: some View {
        VStack(spacing: 8) {
            Text("Subscriptions renew automatically until cancelled in Settings. Lifetime is a one-time purchase.")
                .font(AppTheme.captionFont(11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                if let terms = URL(string: Self.termsOfUseURL) {
                    Link("Terms of Use", destination: terms)
                }
                if let privacy = URL(string: Self.privacyPolicyURL) {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(AppTheme.captionFont(12))
        }
    }

    private func planName(for product: Product) -> String {
        switch product.id {
        case ProStore.monthlyID: "Monthly"
        case ProStore.yearlyID: "Yearly"
        case ProStore.lifetimeID: "Lifetime"
        default: product.displayName
        }
    }

    private func planBadge(for product: Product) -> String? {
        switch product.id {
        case ProStore.yearlyID: "Best value"
        case ProStore.lifetimeID: "Pay once, keep forever"
        default: nil
        }
    }

    private func purchase(_ product: Product) {
        purchasing = true
        Task {
            let success = await ProStore.shared.purchase(product)
            purchasing = false
            if success { dismiss() }
        }
    }
}

#Preview {
    PaywallView()
}
