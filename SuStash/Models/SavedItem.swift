//
//  SavedItem.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-18.
//

import Foundation
import SwiftData

@Model
final class SavedItem {
    var title: String = ""
    var urlString: String = ""
    // Stored as a raw string so adding enum cases never requires a schema
    // migration; `mediaType` below is the typed accessor.
    var mediaTypeRaw: String = MediaType.bookmark.rawValue
    var collection: String?
    var tags: [String] = []

    var sourceApp: String?
    // Downscaled thumbnail fetched at save time; externalStorage keeps the
    // SQLite store lean by spilling blobs to sidecar files.
    @Attribute(.externalStorage) var previewImageData: Data?
    // Full animated GIF data (size-capped at fetch time) for .gif items;
    // previewImageData still holds a static first-frame fallback.
    @Attribute(.externalStorage) var animatedPreviewData: Data?
    // Set after one LinkPresentation fetch (success or failure) so offline
    // saves and dead links aren't refetched on every launch.
    var enrichmentAttempted: Bool = false
    // "Auto" saves from the share extension: the app assigns a collection
    // after enrichment, when the real page title is known.
    var needsAutoCollection: Bool = false
    // True when the user chose (or confirmed) the collection themselves —
    // these items are the training set for the personal auto-filer.
    var collectionSetByUser: Bool = false
    // Sentence embedding of title+host+tags (Float32 buffer), computed at
    // enrichment. Powers smart filing, similar-links, and semantic search.
    var embeddingData: Data?
    var lastOpenedAt: Date?
    // Scraped from product pages at enrichment ("CA$1,099.00"); display-only.
    var productPrice: String?
    // File saves: the bytes live here (externalStorage → sidecar files,
    // CKAsset when syncing); urlString stays "" for file items.
    @Attribute(.externalStorage) var fileData: Data?
    var fileName: String?
    var isFavorite: Bool = false
    var dateSaved: Date = Date()
    var notes: String?
    var estimatedReadingTime: Int?
    var reminderDate: Date?
    var isSharedPublicly: Bool = false

    init(
        title: String,
        urlString: String,
        mediaType: MediaType = .bookmark,
        collection: String? = nil,
        tags: [String] = [],
        sourceApp: String? = nil,
        notes: String? = nil,
        dateSaved: Date = Date()
    ) {
        self.title = title
        self.urlString = urlString
        self.mediaTypeRaw = mediaType.rawValue
        self.collection = collection
        self.tags = tags
        self.sourceApp = sourceApp
        self.notes = notes
        self.dateSaved = dateSaved
    }

    var url: URL? {
        URL(string: urlString)
    }

    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .bookmark }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var isFile: Bool {
        fileData != nil || fileName != nil
    }

    /// Display host, e.g. "youtube.com" for https://www.youtube.com/watch?v=…
    var host: String {
        guard let host = url?.host else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Second line in cells: host for links, type + size for files.
    var displaySubtitle: String {
        guard isFile else { return host }
        if let bytes = fileData?.count, bytes > 0 {
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "\(mediaType.displayName) · \(size)"
        }
        return mediaType.displayName
    }

    /// Friendly source name for filtering, e.g. "YouTube" for youtube.com.
    var sourceName: String {
        let host = self.host
        let knownSources: [(fragment: String, name: String)] = [
            ("youtube", "YouTube"), ("youtu.be", "YouTube"),
            ("tiktok", "TikTok"), ("instagram", "Instagram"),
            ("twitter", "X"), ("x.com", "X"),
            ("reddit", "Reddit"), ("github", "GitHub"),
            ("pinterest", "Pinterest"), ("facebook", "Facebook"),
            ("twitch", "Twitch"), ("spotify", "Spotify"),
            ("linkedin", "LinkedIn"), ("medium", "Medium"),
        ]
        let labels = host.split(separator: ".").map(String.init)
        if let known = knownSources.first(where: { labels.contains($0.fragment) || host == $0.fragment || host.hasSuffix("." + $0.fragment) }) {
            return known.name
        }
        // "swift.org" → "Swift", "news.ycombinator.com" → "Ycombinator"
        guard labels.count >= 2 else { return host.capitalized }
        return labels[labels.count - 2].capitalized
    }
}
