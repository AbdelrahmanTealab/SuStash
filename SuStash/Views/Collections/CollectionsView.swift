//
//  CollectionsView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import Charts
import SwiftUI
import SwiftData
import UIKit

struct CollectionsView: View {
    enum Mode: String, CaseIterable {
        case collections = "Collections"
        case tags = "Tags"
        case media = "Media"
    }

    enum Sort: String, CaseIterable {
        case mostItems = "Most items"
        case name = "A to Z"
        case newest = "Recently added"
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.dateSaved, order: .reverse) private var savedItems: [SavedItem]
    // `-libraryMode media|tags` launch arg presets the segment for
    // simctl-driven screenshots, same pattern as -initialTab.
    @State private var mode: Mode = UserDefaults.standard.string(forKey: "libraryMode")
        .flatMap({ raw in Mode.allCases.first { $0.rawValue.lowercased() == raw.lowercased() } }) ?? .collections
    @State private var sort: Sort = .mostItems
    // Statistics display toggle. `-libraryStats` launch arg (auto-registered
    // into UserDefaults.standard) presets it for simctl-driven screenshots.
    @State private var showStatistics = UserDefaults.standard.bool(forKey: "libraryStats")
    // Dialog state lives here, not on the context-menu buttons — views inside
    // a dismissed menu can't present anything.
    @State private var collectionPendingDelete: String?
    @State private var collectionPendingRename: String?
    @State private var renameText = ""
    // Pinned collections sort first; stored as names in the app group.
    @AppStorage("pinnedCollections", store: AppSettings.store) private var pinnedData = Data()

    private var pinnedNames: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: pinnedData)) ?? []
    }

    private func togglePin(_ name: String) {
        var pinned = pinnedNames
        if !pinned.insert(name).inserted {
            pinned.remove(name)
        }
        withAnimation(.snappy) {
            pinnedData = (try? JSONEncoder().encode(pinned)) ?? Data()
        }
    }

    private struct Group: Identifiable {
        let name: String
        let items: [SavedItem]
        var id: String { name }
        // savedItems arrive sorted newest-first, so first == latest.
        var latest: SavedItem? { items.first }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                if showStatistics && !savedItems.isEmpty {
                    statisticsContent
                } else if mode == .media {
                    if visualItems.isEmpty {
                        mediaEmptyState
                            .frame(maxHeight: .infinity)
                    } else {
                        mediaGrid
                    }
                } else if groups.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else if mode == .collections {
                    collectionGrid
                } else {
                    tagList
                }
            }
            .background(ThemedScreenBackground())
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            showStatistics.toggle()
                        }
                    } label: {
                        Image(systemName: showStatistics ? "square.grid.2x2" : "chart.pie")
                    }
                    .accessibilityLabel(showStatistics ? "Show grid view" : "Show statistics")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .disabled(showStatistics)
                    .accessibilityLabel("Sort")
                }
            }
            .navigationDestination(for: String.self) { groupName in
                GroupDetailView(
                    title: groupName,
                    items: groups.first { $0.name == groupName }?.items ?? []
                )
            }
        }
    }

    // MARK: - Grouping

    private var groups: [Group] {
        let pairs: [(String, SavedItem)] = switch mode {
        case .collections:
            savedItems.compactMap { item in item.collection.map { ($0, item) } }
        case .tags:
            savedItems.flatMap { item in item.tags.map { ($0, item) } }
        case .media:
            []
        }

        let grouped = Dictionary(grouping: pairs, by: { $0.0 })
            .map { Group(name: $0.key, items: $0.value.map(\.1)) }

        let sorted = switch sort {
        case .mostItems:
            grouped.sorted { ($0.items.count, $1.name) > ($1.items.count, $0.name) }
        case .name:
            grouped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest:
            grouped.sorted { ($0.latest?.dateSaved ?? .distantPast) > ($1.latest?.dateSaved ?? .distantPast) }
        }

        // Pinned collections lead within any sort (collections mode only).
        guard mode == .collections else { return sorted }
        let pinned = pinnedNames
        return sorted.filter { pinned.contains($0.name) } + sorted.filter { !pinned.contains($0.name) }
    }

    // MARK: - Collections grid

    private var collectionGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(groups) { group in
                    NavigationLink(value: group.name) {
                        CollectionCard(group: group)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topLeading) {
                        if pinnedNames.contains(group.name) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(AppTheme.accent, in: Circle())
                                .padding(7)
                        }
                    }
                    .contextMenu {
                        Button {
                            togglePin(group.name)
                        } label: {
                            Label(
                                pinnedNames.contains(group.name) ? "Unpin" : "Pin",
                                systemImage: pinnedNames.contains(group.name) ? "pin.slash" : "pin"
                            )
                        }
                        Button {
                            renameText = group.name
                            collectionPendingRename = group.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            collectionPendingDelete = group.name
                        } label: {
                            Label("Delete Collection", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .animation(.snappy, value: groups.map(\.name))
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { collectionPendingDelete != nil },
                set: { if !$0 { collectionPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Collection & Links", role: .destructive) {
                if let name = collectionPendingDelete {
                    deleteCollection(named: name)
                }
                collectionPendingDelete = nil
            }
        } message: {
            Text("This deletes the saved links too and can't be undone.")
        }
        .alert(
            "Rename Collection",
            isPresented: Binding(
                get: { collectionPendingRename != nil },
                set: { if !$0 { collectionPendingRename = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let oldName = collectionPendingRename {
                    renameCollection(from: oldName, to: renameText)
                }
                collectionPendingRename = nil
            }
            Button("Cancel", role: .cancel) { collectionPendingRename = nil }
        }
    }

    private var deleteDialogTitle: String {
        guard let name = collectionPendingDelete else { return "" }
        let count = groups.first { $0.name == name }?.items.count ?? 0
        return "Delete “\(name)” and its \(count) link\(count == 1 ? "" : "s")?"
    }

    private func deleteCollection(named name: String) {
        let descriptor = FetchDescriptor<SavedItem>(predicate: #Predicate { $0.collection == name })
        guard let items = try? modelContext.fetch(descriptor) else { return }
        withAnimation(.snappy) {
            for item in items {
                SpotlightIndexer.remove(urlString: item.urlString)
                modelContext.delete(item)
            }
            try? modelContext.save()
        }
    }

    private func renameCollection(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        let descriptor = FetchDescriptor<SavedItem>(predicate: #Predicate { $0.collection == oldName })
        guard let items = try? modelContext.fetch(descriptor) else { return }
        withAnimation(.snappy) {
            items.forEach { $0.collection = trimmed }
            try? modelContext.save()
        }
    }

    private struct CollectionCard: View {
        let group: Group

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 96)
                    .overlay(thumbnail)
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(AppTheme.headingFont(15))
                        .lineLimit(1)
                    Text("^[\(group.items.count) link](inflect: true)")
                        .font(AppTheme.captionFont(12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        @ViewBuilder
        private var thumbnail: some View {
            if let data = group.items.first(where: { $0.previewImageData != nil })?.previewImageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                let type = group.latest?.mediaType ?? .bookmark
                Rectangle()
                    .fill(AppTheme.badgeColor(for: type).gradient)
                    .overlay(
                        Image(systemName: type.systemImage)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
    }

    // MARK: - Statistics

    @ViewBuilder
    private var statisticsContent: some View {
        switch mode {
        case .collections:
            CollectionBubbleChart(
                counts: statCounts { $0.collection.map { [$0] } ?? [] }
            )
        case .tags:
            TagBarChart(
                counts: statCounts { $0.tags }
            )
        case .media:
            MediaDonutChart(
                counts: statCounts { [$0.mediaType.displayName] },
                colorFor: { name in
                    let type = MediaType.allCases.first { $0.displayName == name } ?? .bookmark
                    return AppTheme.badgeColor(for: type)
                }
            )
        }
    }

    /// (name, count) pairs for the current items, largest first.
    private func statCounts(_ keys: (SavedItem) -> [String]) -> [(name: String, count: Int)] {
        Dictionary(grouping: savedItems.flatMap(keys), by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    // MARK: - Media grid

    /// Every media type with content, in a fixed browse order. Covers both
    /// links (a YouTube video is a video) and saved files.
    private var mediaSections: [(title: String, type: MediaType, items: [SavedItem])] {
        let order: [(String, MediaType)] = [
            ("GIFs", .gif), ("Images", .image), ("Videos", .video),
            ("PDFs", .pdf), ("Audio", .audio), ("Documents", .document),
        ]
        return order.compactMap { title, type in
            let matches = savedItems.filter { $0.mediaType == type }
            return matches.isEmpty ? nil : (title, type, matches)
        }
    }

    private var visualItems: [SavedItem] {
        mediaSections.flatMap(\.items)
    }

    /// Photo-style grids per type: GIFs animate, videos and PDFs show their
    /// thumbnails with a type badge, audio/documents fall back to icon tiles.
    private var mediaGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                ForEach(mediaSections, id: \.title) { section in
                    mediaSectionHeader(section.title, count: section.items.count)
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(section.items) { MediaTile(item: $0) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 20)
        }
    }

    private func mediaSectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppTheme.headingFont(17))
            Text("\(count)")
                .font(AppTheme.captionFont(13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private struct MediaTile: View {
        let item: SavedItem

        var body: some View {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(tileContent)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    typeBadge
                }
                .savedItemInteractions(item)
        }

        @ViewBuilder
        private var typeBadge: some View {
            switch item.mediaType {
            case .gif:
                badgeCapsule(text: "GIF")
            case .pdf:
                badgeCapsule(text: "PDF")
            case .video:
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(5)
            default:
                EmptyView()
            }
        }

        private func badgeCapsule(text: String) -> some View {
            Text(text)
                .font(AppTheme.headingFont(9))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(5)
        }

        @ViewBuilder
        private var tileContent: some View {
            if let gifData = item.animatedPreviewData {
                AnimatedImageView(data: gifData)
            } else if let data = item.previewImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AppTheme.badgeColor(for: item.mediaType).gradient)
                    .overlay(
                        Image(systemName: item.mediaType.systemImage)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
    }

    private var mediaEmptyState: some View {
        ContentUnavailableView {
            Label("No media yet", systemImage: "photo.stack")
        } description: {
            Text("GIFs, images, videos, PDFs, and other files you save will show up here.")
        }
    }

    // MARK: - Tags list

    private var tagList: some View {
        List {
            ForEach(groups) { group in
                NavigationLink(value: group.name) {
                    HStack {
                        Image(systemName: "number")
                            .foregroundStyle(AppTheme.accent)
                        Text(group.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(AppTheme.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                mode == .collections ? "No collections yet" : "No tags yet",
                systemImage: mode == .collections ? "square.grid.2x2" : "number"
            )
        } description: {
            Text(
                mode == .collections
                    ? "Save a link with a collection — or use Auto save and SuStash will organize it for you."
                    : "Add comma-separated tags when saving a link manually."
            )
        }
    }
}

// MARK: - Statistics views

/// Deterministic circle packing: largest bubble at the center, the rest
/// spiral outward to the first collision-free spot. Pure, so it's testable.
enum BubblePacker {
    struct Bubble: Identifiable {
        let name: String
        let count: Int
        let radius: CGFloat
        let center: CGPoint
        var id: String { name }
    }

    static func pack(counts: [(name: String, count: Int)], in size: CGSize, maxBubbles: Int = 12) -> [Bubble] {
        let items = Array(counts.prefix(maxBubbles))
        guard !items.isEmpty, size.width > 60, size.height > 60 else { return [] }

        let maxCount = CGFloat(items.first?.count ?? 1)
        let smallestSide = min(size.width, size.height)
        let maxRadius = smallestSide * 0.24
        let minRadius = max(24, smallestSide * 0.08)
        let padding: CGFloat = 5

        // Area ∝ count reads truthfully; radius scales with sqrt. Then scale
        // everything down to an area budget so a dozen similar-sized bubbles
        // still all fit — greedy packing tops out near ~45% density.
        var radii = items.map { minRadius + (maxRadius - minRadius) * sqrt(CGFloat($0.count) / maxCount) }
        let budget = size.width * size.height * 0.40
        let totalArea = radii.reduce(0) { $0 + .pi * $1 * $1 }
        if totalArea > budget {
            let scale = sqrt(budget / totalArea)
            radii = radii.map { max(18, $0 * scale) }
        }

        let bounds = CGRect(origin: .zero, size: size)
        var placed: [Bubble] = []
        for (index, item) in items.enumerated() {
            let radius = radii[index]
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            var position = center
            if !placed.isEmpty {
                var found = false
                var angle: CGFloat = .pi / 9
                var distance: CGFloat = 1
                while !found, distance < max(size.width, size.height) {
                    let candidate = CGPoint(
                        x: center.x + cos(angle) * distance,
                        y: center.y + sin(angle) * distance * 0.85
                    )
                    let circle = CGRect(
                        x: candidate.x - radius, y: candidate.y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    let collides = placed.contains {
                        hypot($0.center.x - candidate.x, $0.center.y - candidate.y) < $0.radius + radius + padding
                    }
                    if !collides, bounds.insetBy(dx: 1, dy: 1).contains(circle) {
                        position = candidate
                        found = true
                    } else {
                        angle += .pi / 9
                        distance += 1.6
                    }
                }
                guard found else { continue }
            }
            placed.append(Bubble(name: item.name, count: item.count, radius: radius, center: position))
        }
        return placed
    }
}

private struct CollectionBubbleChart: View {
    let counts: [(name: String, count: Int)]

    var body: some View {
        GeometryReader { proxy in
            let bubbles = BubblePacker.pack(counts: counts, in: proxy.size)
            ZStack {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    NavigationLink(value: bubble.name) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.accent.opacity(0.88 - 0.05 * Double(min(index, 8))).gradient)
                            VStack(spacing: 1) {
                                Text(bubble.name)
                                    .font(AppTheme.headingFont(max(11, bubble.radius * 0.24)))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.6)
                                Text("\(bubble.count)")
                                    .font(AppTheme.captionFont(max(10, bubble.radius * 0.18)))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            .padding(6)
                            .frame(width: bubble.radius * 2 - 8)
                        }
                        .frame(width: bubble.radius * 2, height: bubble.radius * 2)
                        .position(bubble.center)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.snappy, value: bubbles.map(\.name))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private struct TagBarChart: View {
    let counts: [(name: String, count: Int)]

    var body: some View {
        let top = Array(counts.prefix(14))
        if top.isEmpty {
            ContentUnavailableView {
                Label("No tags yet", systemImage: "number")
            } description: {
                Text("Tag links when saving manually and their stats show up here.")
            }
        } else {
            ScrollView {
                Chart(top, id: \.name) { entry in
                    BarMark(
                        x: .value("Links", entry.count),
                        y: .value("Tag", entry.name)
                    )
                    .foregroundStyle(AppTheme.accent.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing, spacing: 4) {
                        Text("\(entry.count)")
                            .font(AppTheme.captionFont(11))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisValueLabel()
                            .font(AppTheme.captionFont(12))
                    }
                }
                .frame(height: CGFloat(top.count) * 34 + 20)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct MediaDonutChart: View {
    let counts: [(name: String, count: Int)]
    let colorFor: (String) -> Color

    var body: some View {
        let total = counts.reduce(0) { $0 + $1.count }
        ScrollView {
            VStack(spacing: 18) {
                Chart(counts, id: \.name) { entry in
                    SectorMark(
                        angle: .value("Links", entry.count),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(colorFor(entry.name).gradient)
                    .cornerRadius(4)
                }
                .frame(height: 240)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("\(total)")
                            .font(AppTheme.titleFont(28))
                        Text("links")
                            .font(AppTheme.captionFont(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)

                VStack(spacing: 8) {
                    ForEach(counts, id: \.name) { entry in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(colorFor(entry.name))
                                .frame(width: 10, height: 10)
                            Text(entry.name)
                                .font(AppTheme.bodyFont(14))
                            Spacer()
                            Text("\(entry.count)")
                                .font(AppTheme.captionFont(13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Detail

struct GroupDetailView: View {
    let title: String
    let items: [SavedItem]

    var body: some View {
        List {
            ForEach(items) { item in
                SavedItemRow(item: item)
                    .listRowBackground(AppTheme.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ThemedScreenBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    CollectionsView()
        .modelContainer(for: SavedItem.self, inMemory: true)
}
