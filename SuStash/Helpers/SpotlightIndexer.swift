//
//  SpotlightIndexer.swift
//  SuStash
//
//  Mirrors saved links into CoreSpotlight so they surface in iPhone search.
//  The item's URL string doubles as the searchable identifier, so opening a
//  result maps straight back to the SavedItem.
//

import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

enum SpotlightIndexer {
    static let domain = "savedLinks"
    private static let logger = Logger(subsystem: "com.atealab.SuStash", category: "SpotlightIndexer")

    /// Full mirror of the library. Libraries are small (hundreds, not
    /// millions), so a wholesale reindex after changes beats bookkeeping
    /// individual diffs.
    static func reindex(_ items: [SavedItem]) {
        let searchableItems = items.map { item in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.url)
            attributes.title = item.title
            attributes.contentDescription = [item.collection, item.notes, item.host]
                .compactMap { $0 }
                .joined(separator: " — ")
            attributes.url = item.url
            attributes.keywords = item.tags + [item.sourceName, item.mediaType.displayName]
            attributes.thumbnailData = item.previewImageData

            let searchable = CSSearchableItem(
                uniqueIdentifier: item.urlString,
                domainIdentifier: domain,
                attributeSet: attributes
            )
            searchable.expirationDate = .distantFuture
            return searchable
        }

        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !searchableItems.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
                if let error {
                    logger.error("Spotlight indexing failed: \(error)")
                }
            }
        }
    }

    static func remove(urlString: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [urlString]) { _ in }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}
