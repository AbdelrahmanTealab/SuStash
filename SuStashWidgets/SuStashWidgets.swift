//
//  SuStashWidgets.swift
//  SuStashWidgets
//
//  Home-screen widgets reading the shared SwiftData store in the app group.
//  Rows deep-link through sustash://open?u=… so the app can mark the item
//  opened before forwarding to the browser.
//

import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

@main
struct SuStashWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecentSavesWidget()
        CollectionWidget()
    }
}

// MARK: - Store access

/// Lightweight snapshot of a SavedItem — timeline entries must not hold
/// live model objects.
struct WidgetLink: Identifiable, Hashable {
    let urlString: String
    let title: String
    let host: String
    let mediaTypeRaw: String
    let imageData: Data?

    var id: String { urlString }

    var mediaType: MediaType { MediaType(rawValue: mediaTypeRaw) ?? .bookmark }

    var deepLink: URL {
        let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? urlString
        return URL(string: "sustash://open?u=\(encoded)") ?? URL(string: "sustash://open")!
    }

    init(_ item: SavedItem) {
        urlString = item.urlString
        title = item.title
        host = item.host
        mediaTypeRaw = item.mediaTypeRaw
        imageData = item.previewImageData
    }
}

enum WidgetStore {
    static func recentLinks(limit: Int, collection: String? = nil) -> [WidgetLink] {
        var descriptor = FetchDescriptor<SavedItem>(
            sortBy: [SortDescriptor(\.dateSaved, order: .reverse)]
        )
        if let collection {
            descriptor.predicate = #Predicate { $0.collection == collection }
        }
        descriptor.fetchLimit = limit
        let context = ModelContext(SharedStore.container)
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map(WidgetLink.init)
    }

    static func distinctCollections() -> [String] {
        let context = ModelContext(SharedStore.container)
        let items = (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
        return Array(Set(items.compactMap(\.collection))).sorted()
    }
}

// MARK: - Recent saves widget

struct RecentSavesEntry: TimelineEntry {
    let date: Date
    let links: [WidgetLink]
}

struct RecentSavesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentSavesEntry {
        RecentSavesEntry(date: .now, links: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentSavesEntry) -> Void) {
        completion(RecentSavesEntry(date: .now, links: WidgetStore.recentLinks(limit: 5)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentSavesEntry>) -> Void) {
        let entry = RecentSavesEntry(date: .now, links: WidgetStore.recentLinks(limit: 5))
        // The app reloads timelines on every data change; this is a backstop.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct RecentSavesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentSavesWidget", provider: RecentSavesProvider()) { entry in
            RecentSavesView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Recent Saves")
        .description("Your latest saved links, one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentSavesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentSavesEntry

    var body: some View {
        if entry.links.isEmpty {
            emptyView
        } else if family == .systemSmall {
            SingleLinkView(link: entry.links[0])
        } else {
            LinkListView(
                title: "Recent Saves",
                systemImage: "tray.full.fill",
                links: Array(entry.links.prefix(family == .systemMedium ? 2 : 5))
            )
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Share a link to SuStash and it shows up here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Collection widget

struct SelectCollectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Collection"
    static var description = IntentDescription("Pick which collection this widget shows.")

    @Parameter(title: "Collection", optionsProvider: CollectionOptionsProvider())
    var collection: String?

    struct CollectionOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> [String] {
            WidgetStore.distinctCollections()
        }
    }
}

struct CollectionEntry: TimelineEntry {
    let date: Date
    let collectionName: String?
    let links: [WidgetLink]
}

struct CollectionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CollectionEntry {
        CollectionEntry(date: .now, collectionName: nil, links: [])
    }

    func snapshot(for configuration: SelectCollectionIntent, in context: Context) async -> CollectionEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectCollectionIntent, in context: Context) async -> Timeline<CollectionEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(3600)))
    }

    private func entry(for configuration: SelectCollectionIntent) -> CollectionEntry {
        let name = configuration.collection ?? WidgetStore.distinctCollections().first
        let links = name.map { WidgetStore.recentLinks(limit: 5, collection: $0) } ?? []
        return CollectionEntry(date: .now, collectionName: name, links: links)
    }
}

struct CollectionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "CollectionWidget",
            intent: SelectCollectionIntent.self,
            provider: CollectionProvider()
        ) { entry in
            CollectionWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Collection")
        .description("Latest links from a collection of your choice.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CollectionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CollectionEntry

    var body: some View {
        if let name = entry.collectionName, !entry.links.isEmpty {
            if family == .systemSmall {
                SingleLinkView(link: entry.links[0], badge: name)
            } else {
                LinkListView(
                    title: name,
                    systemImage: "square.grid.2x2.fill",
                    links: Array(entry.links.prefix(family == .systemMedium ? 2 : 5))
                )
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Long-press to choose a collection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Shared widget views

struct SingleLinkView: View {
    let link: WidgetLink
    var badge: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = link.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            } else {
                Rectangle().fill(AppTheme.badgeColor(for: link.mediaType).gradient)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(link.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
            .padding(10)
        }
        .widgetURL(link.deepLink)
    }
}

struct LinkListView: View {
    let title: String
    let systemImage: String
    let links: [WidgetLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(AppTheme.accent)

            ForEach(links) { link in
                Link(destination: link.deepLink) {
                    HStack(spacing: 8) {
                        thumbnail(for: link)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(link.host)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func thumbnail(for link: WidgetLink) -> some View {
        if let data = link.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: link.mediaType.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    AppTheme.badgeColor(for: link.mediaType).gradient,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
    }
}
