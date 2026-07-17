//
//  LinkMetadataEnricher.swift
//  SuStash
//
//  Fetches real titles and thumbnails for saved links — once, at save time.
//  Cells never do network work, so scrolling stays smooth.
//

import Foundation
import LinkPresentation
import OSLog
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum LinkMetadataEnricher {
    private static let logger = Logger(subsystem: "com.atealab.SuStash", category: "LinkMetadataEnricher")

    /// Longest edge of stored thumbnails. Big enough for a full-width card
    /// on a 3x screen, small enough to keep the store and scroll decoding cheap.
    private static let maxThumbnailDimension: CGFloat = 720

    @MainActor private static var isRunning = false

    /// Enriches every item that hasn't had a fetch attempt yet. Items are
    /// saved one by one, so results appear in the UI as they arrive and a
    /// killed app loses at most one in-flight fetch. Re-entrant calls
    /// (rapid background/foreground cycles) coalesce into the running pass.
    @MainActor
    static func enrichPendingItems(in context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // Filtered in memory, not via #Predicate: embeddingData uses
        // externalStorage, which SwiftData cannot evaluate in a predicate —
        // the fetch would throw and silently skip enrichment entirely.
        // Included cases: fresh saves, re-shares asking for auto-filing,
        // and embedding backfill for pre-intelligence items (local-only).
        let descriptor = FetchDescriptor<SavedItem>(
            sortBy: [SortDescriptor(\.dateSaved, order: .reverse)]
        )
        guard let allItems = try? context.fetch(descriptor) else { return }
        let items = allItems.filter {
            !$0.enrichmentAttempted || $0.needsAutoCollection || $0.embeddingData == nil
        }
        guard !items.isEmpty else { return }
        // .notice persists to the log store — enrichment issues were
        // invisible at .info during debugging.
        logger.notice("Enriching \(items.count) item(s); embedder available: \(LinkEmbedder.isAvailable)")

        for item in items {
            if item.enrichmentAttempted {
                computeEmbeddingIfNeeded(item)
                autoOrganizeIfNeeded(item, in: context)
                saveQuietly(context)
                continue
            }
            guard let url = item.url, url.scheme == "http" || url.scheme == "https" else {
                item.enrichmentAttempted = true
                computeEmbeddingIfNeeded(item)
                autoOrganizeIfNeeded(item, in: context)
                saveQuietly(context)
                continue
            }

            let fetched = await fetchMetadata(for: url, wantsProductDetails: item.mediaType == .product)
            // The item may have been deleted while the network call ran.
            guard !item.isDeleted else { continue }

            item.enrichmentAttempted = true
            if let title = fetched.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                item.title = title
            }
            if let imageData = fetched.imageData {
                withAnimation(.snappy) {
                    item.previewImageData = imageData
                }
            }
            if let price = fetched.priceText {
                item.productPrice = price
            }
            if let gifData = fetched.animatedImageData {
                withAnimation(.snappy) {
                    item.animatedPreviewData = gifData
                }
                // A static first frame keeps collection cards and exports cheap.
                if item.previewImageData == nil, let firstFrame = UIImage(data: gifData) {
                    item.previewImageData = thumbnailData(from: firstFrame)
                }
            }
            computeEmbeddingIfNeeded(item)
            autoOrganizeIfNeeded(item, in: context)
            saveQuietly(context)
        }
    }

    /// Embed once the real title is known. Cheap (~ms) and idempotent.
    @MainActor
    private static func computeEmbeddingIfNeeded(_ item: SavedItem) {
        guard item.embeddingData == nil else { return }
        let text = LinkEmbedder.embeddingText(title: item.title, host: item.host, tags: item.tags)
        guard let vector = LinkEmbedder.vector(for: text) else { return }
        item.embeddingData = LinkEmbedder.data(from: vector)
    }

    /// Runs after enrichment so the classifiers see the real page title.
    /// Pro users get the personal filer first — it knows how *they* file —
    /// with the rules classifier as the fallback for everyone.
    @MainActor
    private static func autoOrganizeIfNeeded(_ item: SavedItem, in context: ModelContext) {
        guard item.needsAutoCollection else { return }
        item.needsAutoCollection = false
        guard item.collection == nil else { return }

        var personalPick: String?
        if ProStore.shared.isPro, let data = item.embeddingData {
            personalPick = SmartFiler.classifyAgainstLibrary(
                vector: LinkEmbedder.floats(from: data),
                in: context
            )?.collection
        }

        withAnimation(.snappy) {
            item.collection = personalPick ?? CollectionClassifier.suggestCollection(
                title: item.title,
                urlString: item.urlString,
                mediaType: item.mediaType
            )
        }
    }

    @MainActor
    private static func saveQuietly(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save enrichment: \(error)")
        }
    }

    private struct FetchedMetadata {
        var title: String?
        var imageData: Data?
        var animatedImageData: Data?
        var priceText: String?
    }

    /// GIFs above this size get a static preview only — keeps the store and
    /// list scrolling sane if someone saves a 50 MB monster.
    private static let maxAnimatedBytes = 12_000_000

    private static func fetchMetadata(for url: URL, wantsProductDetails: Bool = false) async -> FetchedMetadata {
        var fetched = FetchedMetadata()

        // Direct .gif links skip the metadata dance — the URL is the content.
        if url.pathExtension.lowercased() == "gif" {
            fetched.animatedImageData = await downloadGIF(from: url)
        }

        let provider = LPMetadataProvider()
        provider.timeout = 15

        if let metadata = try? await provider.startFetchingMetadata(for: url) {
            fetched.title = metadata.title
            if let imageProvider = metadata.imageProvider {
                // Pages on GIF hosts (Tenor, Giphy) usually expose the GIF as
                // their preview image; grab the animated original when offered.
                if fetched.animatedImageData == nil,
                   imageProvider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
                    fetched.animatedImageData = await loadGIFData(from: imageProvider)
                }
                fetched.imageData = await loadThumbnailData(from: imageProvider)
            }
        }

        // Storefronts often defeat LinkPresentation (no preview image) and
        // are the only place prices live — go to the page's OpenGraph tags.
        if fetched.imageData == nil || (wantsProductDetails && fetched.priceText == nil) {
            if let html = await OpenGraphScraper.fetchHTMLHead(from: url) {
                if wantsProductDetails {
                    fetched.priceText = OpenGraphScraper.price(inHTML: html)
                }
                if fetched.imageData == nil,
                   let imageURL = OpenGraphScraper.imageURL(inHTML: html, relativeTo: url),
                   let (data, _) = try? await URLSession.shared.data(from: imageURL),
                   let image = UIImage(data: data) {
                    fetched.imageData = thumbnailData(from: image)
                }
            }
        }
        return fetched
    }

    private static func downloadGIF(from url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        guard data.count <= maxAnimatedBytes else { return nil }
        let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard mime.isEmpty || mime.contains("gif") || mime.contains("octet-stream") else { return nil }
        return data
    }

    private static func loadGIFData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.gif.identifier) { data, _ in
                if let data, data.count <= maxAnimatedBytes {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadThumbnailData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: thumbnailData(from: image))
            }
        }
    }

    // MARK: - OpenGraph fallback

    /// Minimal OpenGraph/meta scraping for pages LinkPresentation can't
    /// handle (storefronts especially). Regex over the document head only —
    /// robust enough for meta tags, no HTML parser dependency.
    enum OpenGraphScraper {
        static func fetchHTMLHead(from url: URL, byteLimit: Int = 400_000) async -> String? {
            guard url.scheme == "https" || url.scheme == "http" else { return nil }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return String(decoding: data.prefix(byteLimit), as: UTF8.self)
        }

        static func imageURL(inHTML html: String, relativeTo base: URL) -> URL? {
            guard let content = metaContent(inHTML: html, forProperties: ["og:image", "og:image:url", "twitter:image"]) else {
                return nil
            }
            return URL(string: content, relativeTo: base)?.absoluteURL
        }

        /// "CA$1,099.00"-style display string, or nil when the page exposes
        /// no machine-readable price.
        static func price(inHTML html: String) -> String? {
            let amount = metaContent(inHTML: html, forProperties: ["product:price:amount", "og:price:amount"])
                ?? jsonLDValue(inHTML: html, forKey: "price")
            guard var amount, !amount.isEmpty else { return nil }
            amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            guard amount.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }

            let currency = metaContent(inHTML: html, forProperties: ["product:price:currency", "og:price:currency"])
                ?? jsonLDValue(inHTML: html, forKey: "priceCurrency")
            return format(amount: amount, currency: currency?.uppercased())
        }

        private static func format(amount: String, currency: String?) -> String {
            let symbols: [String: String] = [
                "USD": "$", "CAD": "CA$", "EUR": "€", "GBP": "£", "JPY": "¥", "AUD": "A$",
            ]
            guard let currency else { return amount }
            if let symbol = symbols[currency] {
                return symbol + amount
            }
            return "\(currency) \(amount)"
        }

        /// <meta property="og:x" content="…"> in either attribute order,
        /// with property= or name=, single or double quotes.
        private static func metaContent(inHTML html: String, forProperties properties: [String]) -> String? {
            for property in properties {
                let escaped = NSRegularExpression.escapedPattern(for: property)
                let patterns = [
                    "<meta[^>]+(?:property|name)=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']+)[\"']",
                    "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(escaped)[\"']",
                ]
                for pattern in patterns {
                    if let match = firstCapture(pattern, in: html) {
                        return match
                    }
                }
            }
            return nil
        }

        /// "price": "1099.99" or "priceCurrency": "USD" inside JSON-LD blocks.
        /// Callers validate the shape (price() requires digits), so the
        /// capture accepts alphanumerics for currency codes too.
        private static func jsonLDValue(inHTML html: String, forKey key: String) -> String? {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            return firstCapture("\"\(escaped)\"\\s*:\\s*\"?([A-Za-z0-9][A-Za-z0-9.,]*)", in: html)
        }

        private static func firstCapture(_ pattern: String, in text: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    /// Downscale + JPEG-encode off the source image's full resolution, so a
    /// 4K og:image doesn't land in the store or in scroll-time decoding.
    static func thumbnailData(from image: UIImage) -> Data? {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > 0 else { return nil }

        let scale = min(1, maxThumbnailDimension / longestEdge)
        let targetSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
