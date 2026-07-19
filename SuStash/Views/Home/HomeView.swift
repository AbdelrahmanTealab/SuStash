//
//  HomeView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

enum HomeViewMode: String, CaseIterable, Identifiable {
    case list
    case grid
    case icons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        case .icons: "Icons"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .icons: "square.grid.3x3"
        }
    }
}

enum HomeFilter: Equatable {
    case recents
    case favorites
    case source(String)
    case tag(String)

    var title: String {
        switch self {
        case .recents: "Recents"
        case .favorites: "Favorites"
        case .source(let name): name
        case .tag(let tag): "#\(tag)"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.dateSaved, order: .reverse) private var savedItems: [SavedItem]

    /// Pending + button save, shown in the Auto/Manual composer sheet.
    struct ComposerPayload: Identifiable {
        let id = UUID()
        let input: ComposerInput
        var fileData: Data?
        var fileName: String?
    }

    @State private var filter: HomeFilter = .recents
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showSettings = false
    @State private var composer: ComposerPayload?
    @State private var pasteMessage: String?
    @FocusState private var searchFieldFocused: Bool
    @AppStorage(AppSettings.homeViewModeKey, store: AppSettings.store) private var viewModeRaw = HomeViewMode.list.rawValue

    private var viewMode: HomeViewMode {
        HomeViewMode(rawValue: viewModeRaw) ?? .list
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isSearching {
                searchField
            }

            if filteredItems.isEmpty {
                emptyState
                    .frame(maxHeight: .infinity)
            } else {
                switch viewMode {
                case .list: itemList
                case .grid: itemGrid
                case .icons: itemIcons
                }
            }
        }
        .background(ThemedScreenBackground())
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $composer) { payload in
            SaveComposerView(
                input: payload.input,
                onSave: { metadata in
                    persistComposerSave(metadata, payload: payload)
                    composer = nil
                },
                onCancel: { composer = nil }
            )
        }
        .alert(
            pasteMessage ?? "",
            isPresented: Binding(
                get: { pasteMessage != nil },
                set: { if !$0 { pasteMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(filter.title)
                .font(AppTheme.titleFont(30))
                .lineLimit(1)

            Menu {
                filterMenuContent
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(7)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Filter saved links")

            Spacer()

            Menu {
                Picker("View", selection: $viewModeRaw) {
                    ForEach(HomeViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
            } label: {
                Image(systemName: viewMode.systemImage)
            }
            .accessibilityLabel("Change view layout")
            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
            Button(action: saveFromClipboard) {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Save link from clipboard")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        .buttonStyle(.plain)
        .font(.title3)
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .animation(.snappy, value: filter)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search titles, tags, notes…", text: $searchText)
                .font(AppTheme.bodyFont(15))
                .focused($searchFieldFocused)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var filterMenuContent: some View {
        Button {
            filter = .recents
        } label: {
            Label("Recents", systemImage: "clock")
        }

        let favoriteCount = savedItems.filter(\.isFavorite).count
        if favoriteCount > 0 {
            Button {
                filter = .favorites
            } label: {
                Label("Favorites (\(favoriteCount))", systemImage: "star")
            }
        }

        let sources = rankedSources
        if !sources.isEmpty {
            Section("Sources") {
                ForEach(sources, id: \.name) { source in
                    Button("\(source.name) (\(source.count))") {
                        filter = .source(source.name)
                    }
                }
            }
        }

        let tags = rankedTags
        if !tags.isEmpty {
            Section("Tags") {
                ForEach(tags, id: \.name) { tag in
                    Button("#\(tag.name) (\(tag.count))") {
                        filter = .tag(tag.name)
                    }
                }
            }
        }
    }

    private var itemList: some View {
        List {
            ForEach(filteredItems) { item in
                SavedItemRow(item: item)
                    .listRowBackground(AppTheme.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .animation(.snappy, value: filteredItems.count)
    }

    private var itemGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(filteredItems) { item in
                    HomeGridCard(item: item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .animation(.snappy, value: filteredItems.count)
    }

    private var itemIcons: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(filteredItems) { item in
                    HomeIconTile(item: item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .animation(.snappy, value: filteredItems.count)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                filter == .recents && searchText.isEmpty ? "No saved links yet" : "Nothing here",
                systemImage: filter == .recents && searchText.isEmpty ? "tray" : "line.3.horizontal.decrease.circle"
            )
        } description: {
            Text(
                filter == .recents && searchText.isEmpty
                    ? "Share a link from any app to SuStash and it will land here."
                    : "No saved links match."
            )
        }
    }

    // MARK: - Actions

    private func toggleSearch() {
        withAnimation(.snappy) {
            isSearching.toggle()
            if isSearching {
                searchFieldFocused = true
            } else {
                searchText = ""
            }
        }
    }

    /// The + button: detect what's on the clipboard (link, image, GIF, or
    /// PDF) and open the Auto/Manual composer for it — same sheet as the
    /// share extension, saving happens only on Save.
    private func saveFromClipboard() {
        let pasteboard = UIPasteboard.general

        if let url = pasteboard.url ?? pasteboard.string.flatMap(Self.firstURL(in:)) {
            if savedItems.contains(where: { $0.urlString == url.absoluteString }) {
                pasteMessage = "That link is already saved."
                return
            }
            composer = ComposerPayload(input: .url(url))
            return
        }

        if let gifData = pasteboard.data(forPasteboardType: UTType.gif.identifier) {
            presentFileComposer(data: gifData, name: "Pasted GIF.gif", type: .gif)
            return
        }
        if let image = pasteboard.image, let data = image.jpegData(compressionQuality: 0.9) {
            presentFileComposer(data: data, name: "Pasted Image.jpg", type: .image)
            return
        }
        if let pdfData = pasteboard.data(forPasteboardType: UTType.pdf.identifier) {
            presentFileComposer(data: pdfData, name: "Pasted Document.pdf", type: .pdf)
            return
        }

        pasteMessage = "No link, image, or document found on the clipboard."
    }

    private func presentFileComposer(data: Data, name: String, type: MediaType) {
        let oversized = data.count > AppGroup.maxSavedFileBytes
        composer = ComposerPayload(
            input: .file(displayName: name, mediaType: type, oversized: oversized),
            fileData: oversized ? nil : data,
            fileName: name
        )
    }

    /// Same semantics as the share-extension importer, but writes straight
    /// into the store since we're already in the app.
    private func persistComposerSave(_ metadata: SharedLinkMetadata, payload: ComposerPayload) {
        let collection = metadata.collection.isEmpty ? nil : metadata.collection

        let item: SavedItem
        switch payload.input {
        case .url(let url):
            item = SavedItem(
                title: url.host ?? url.absoluteString,
                urlString: url.absoluteString,
                mediaType: MediaType(rawValue: metadata.mediaType) ?? .inferred(from: url),
                collection: collection,
                tags: metadata.tags,
                notes: metadata.notes
            )
        case .file(let name, let type, _):
            guard let data = payload.fileData else { return }
            item = SavedItem(
                title: (payload.fileName as NSString?)?.deletingPathExtension ?? name,
                urlString: "",
                mediaType: type,
                collection: collection,
                tags: metadata.tags,
                notes: metadata.notes
            )
            item.fileData = data
            item.fileName = payload.fileName
        }
        item.needsAutoCollection = (metadata.autoOrganize ?? false) && collection == nil
        item.collectionSetByUser = collection != nil

        withAnimation(.snappy) {
            modelContext.insert(item)
            try? modelContext.save()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            await LinkMetadataEnricher.enrichPendingItems(in: modelContext)
        }
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return match?.url
    }

    // MARK: - Filtering

    private var filteredItems: [SavedItem] {
        let base: [SavedItem] = switch filter {
        case .recents:
            savedItems
        case .favorites:
            savedItems.filter(\.isFavorite)
        case .source(let name):
            savedItems.filter { $0.sourceName == name }
        case .tag(let tag):
            savedItems.filter { $0.tags.contains(tag) }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }

        let textMatches = base.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.host.localizedCaseInsensitiveContains(query)
                || (item.collection?.localizedCaseInsensitiveContains(query) ?? false)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                || (item.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }

        // Semantic layer: "pasta" also finds "creamy garlic spaghetti".
        // Appended after exact matches so literal hits always rank first.
        guard query.count >= 3, let queryVector = LinkEmbedder.vector(for: query) else {
            return textMatches
        }
        let matchedIDs = Set(textMatches.map(\.persistentModelID))
        let semanticMatches = SmartFiler.similarItems(
            to: queryVector,
            among: base.filter { !matchedIDs.contains($0.persistentModelID) },
            minimumSimilarity: 0.55,
            limit: 10
        )
        return textMatches + semanticMatches
    }

    private var rankedSources: [(name: String, count: Int)] {
        ranked(savedItems.map(\.sourceName))
    }

    private var rankedTags: [(name: String, count: Int)] {
        ranked(savedItems.flatMap(\.tags))
    }

    private func ranked(_ values: [String]) -> [(name: String, count: Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }
}

// MARK: - Grid & icon cells

private struct HomeGridCard: View {
    let item: SavedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Overlay pattern: the image can never dictate the cell's width
            // (a wide og:image would otherwise blow the card out of its column).
            Color.clear
                .frame(height: 108)
                .overlay(artwork)
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
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        }
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(.black.opacity(0.5), in: Circle())
                    .padding(6)
            }
        }
        .savedItemInteractions(item)
    }

    @ViewBuilder
    private var artwork: some View {
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

private struct HomeIconTile: View {
    let item: SavedItem

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(artwork)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .savedItemInteractions(item)
    }

    @ViewBuilder
    private var artwork: some View {
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
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                )
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: SavedItem.self, inMemory: true)
}
