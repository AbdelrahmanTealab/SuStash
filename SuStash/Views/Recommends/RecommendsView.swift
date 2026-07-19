//
//  RecommendsView.swift
//  SuStash
//
//  "Rediscover" — resurfaces what you saved and forgot. Fully offline:
//  picks come from your own library (unopened links, favorites, oldest
//  saves), not from an external recommendation service.
//

import SwiftUI
import SwiftData
import UIKit

struct RecommendsView: View {
    @Query(sort: \SavedItem.dateSaved, order: .reverse) private var savedItems: [SavedItem]
    @State private var shuffleSeed = UInt64.random(in: .min ... .max)
    @State private var proStore = ProStore.shared
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if savedItems.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .background(ThemedScreenBackground())
            .navigationTitle("Rediscover")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            shuffleSeed = UInt64.random(in: .min ... .max)
                        }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .accessibilityLabel("Shuffle picks")
                }
            }
        }
    }

    private var content: some View {
        List {
            if proStore.isPro {
                if let suggestion = becauseYouSaved {
                    Section {
                        ForEach(suggestion.picks) { item in
                            SavedItemRow(item: item)
                                .listRowBackground(AppTheme.card)
                        }
                    } header: {
                        Label("Because you saved “\(suggestion.anchor.title)”", systemImage: "sparkles")
                    }
                }
            } else if savedItems.count >= 5 {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Smart suggestions")
                                    .font(AppTheme.headingFont(15))
                                Text("Pro finds links similar to what you actually open.")
                                    .font(AppTheme.captionFont(13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.card)
                }
            }

            if !unopenedPicks.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(unopenedPicks) { item in
                                RediscoverCard(item: item)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Still unopened")
                } footer: {
                    Text("Saved but never visited — tap shuffle for new picks.")
                }
            }

            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { item in
                        SavedItemRow(item: item)
                            .listRowBackground(AppTheme.card)
                    }
                }
            }

            if !backlog.isEmpty {
                Section("From the vault") {
                    ForEach(backlog) { item in
                        SavedItemRow(item: item)
                            .listRowBackground(AppTheme.card)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// Anchor = the item the user most recently engaged with (opened or
    /// favorited); picks = unopened links semantically nearest to it.
    private var becauseYouSaved: (anchor: SavedItem, picks: [SavedItem])? {
        guard let anchor = savedItems
            .filter({ ($0.lastOpenedAt != nil || $0.isFavorite) && $0.embeddingData != nil })
            .max(by: { ($0.lastOpenedAt ?? $0.dateSaved) < ($1.lastOpenedAt ?? $1.dateSaved) }),
            let anchorData = anchor.embeddingData
        else { return nil }

        let anchorVector = LinkEmbedder.floats(from: anchorData)
        guard !anchorVector.isEmpty else { return nil }

        let candidates = savedItems.filter {
            $0.lastOpenedAt == nil && $0.persistentModelID != anchor.persistentModelID
        }
        // Higher bar than filing: a weakly-related suggestion is worse than
        // no section. Small libraries will often show nothing here at first.
        let picks = SmartFiler.similarItems(to: anchorVector, among: candidates, minimumSimilarity: 0.62, limit: 4)
        return picks.isEmpty ? nil : (anchor, picks)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to rediscover yet", systemImage: "sparkles")
        } description: {
            Text("Once you save a few links, SuStash will resurface the ones you haven't gotten to.")
        }
    }

    // MARK: - Picks

    /// Up to 6 never-opened links, in a stable shuffle keyed by the seed so
    /// the row doesn't reshuffle on every SwiftData change. Excludes the
    /// vault items so a link never shows in two sections at once.
    private var unopenedPicks: [SavedItem] {
        var generator = SeededGenerator(seed: shuffleSeed)
        let vaultIDs = Set(backlog.map(\.persistentModelID))
        return savedItems
            .filter { $0.lastOpenedAt == nil && !vaultIDs.contains($0.persistentModelID) }
            .shuffled(using: &generator)
            .prefix(6)
            .map { $0 }
    }

    private var favorites: [SavedItem] {
        Array(savedItems.filter(\.isFavorite).prefix(5))
    }

    /// Oldest never-opened saves — the back of the drawer.
    private var backlog: [SavedItem] {
        Array(
            savedItems
                .filter { $0.lastOpenedAt == nil }
                .suffix(3)
                .reversed()
        )
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }
}

private struct RediscoverCard: View {
    let item: SavedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .frame(width: 168, height: 96)
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.headingFont(13))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.displaySubtitle)
                    .font(AppTheme.captionFont(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 168, height: 62, alignment: .topLeading)
        }
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .savedItemInteractions(item)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = item.previewImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(AppTheme.badgeColor(for: item.mediaType).gradient)
                .overlay(
                    Image(systemName: item.mediaType.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                )
        }
    }
}

#Preview {
    RecommendsView()
        .modelContainer(for: SavedItem.self, inMemory: true)
}
