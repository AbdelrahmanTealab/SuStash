//
//  SuStashTests.swift
//  SuStashTests
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import XCTest
import SwiftData
import UIKit
@testable import SuStash

@MainActor
final class SharedLinkImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suiteName = "SharedLinkImporterTests"

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: SavedItem.self, configurations: config)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func enqueue(_ items: [SharedLinkMetadata]) throws {
        defaults.set(try JSONEncoder().encode(items), forKey: AppGroup.sharedLinkQueueKey)
    }

    private func fetchAll() throws -> [SavedItem] {
        try container.mainContext.fetch(FetchDescriptor<SavedItem>())
    }

    private func drain() {
        SharedLinkImporter.drainPendingSharedLinks(into: container.mainContext, defaults: defaults)
    }

    func testDrainImportsQueuedLinksAndClearsQueue() throws {
        try enqueue([
            SharedLinkMetadata(url: "https://www.youtube.com/watch?v=abc", collection: "Watch Later", tags: ["swift", " ios "], mediaType: "video", notes: "great talk"),
            SharedLinkMetadata(url: "https://swift.org/blog", collection: "", tags: [], mediaType: "article", notes: nil),
        ])

        drain()

        let items = try fetchAll()
        XCTAssertEqual(items.count, 2)
        XCTAssertNil(defaults.data(forKey: AppGroup.sharedLinkQueueKey), "queue should be cleared after a successful import")

        let video = try XCTUnwrap(items.first { $0.urlString.contains("youtube") })
        XCTAssertEqual(video.title, "youtube.com")
        XCTAssertEqual(video.mediaType, .video)
        XCTAssertEqual(video.collection, "Watch Later")
        XCTAssertEqual(video.tags, ["swift", "ios"], "tags should be trimmed")
        XCTAssertEqual(video.notes, "great talk")

        let article = try XCTUnwrap(items.first { $0.urlString.contains("swift.org") })
        XCTAssertNil(article.collection, "empty collection should become nil")
    }

    func testDrainIsIdempotentAcrossRetries() throws {
        let metadata = SharedLinkMetadata(url: "https://example.com", collection: "", tags: [], mediaType: "bookmark", notes: nil, dateSaved: Date(timeIntervalSinceReferenceDate: 1_000_000))
        try enqueue([metadata])
        drain()

        // Simulate a crash after save but before the queue was cleared:
        // the same payload is still queued on the next launch.
        try enqueue([metadata])
        drain()

        XCTAssertEqual(try fetchAll().count, 1, "re-draining the same payload must not duplicate items")
    }

    func testUnreadableQueueIsDiscarded() throws {
        defaults.set(Data("not json".utf8), forKey: AppGroup.sharedLinkQueueKey)

        drain()

        XCTAssertEqual(try fetchAll().count, 0)
        XCTAssertNil(defaults.data(forKey: AppGroup.sharedLinkQueueKey), "poisoned queue must be discarded, not retried forever")
    }

    func testInvalidURLIsSkippedWithoutBlockingOthers() throws {
        try enqueue([
            SharedLinkMetadata(url: "", collection: "", tags: [], mediaType: "bookmark", notes: nil),
            SharedLinkMetadata(url: "https://example.com", collection: "", tags: [], mediaType: "bookmark", notes: nil),
        ])

        drain()

        let items = try fetchAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.urlString, "https://example.com")
    }

    func testUnknownMediaTypeFallsBackToInference() throws {
        try enqueue([
            SharedLinkMetadata(url: "https://www.youtube.com/watch?v=abc", collection: "", tags: [], mediaType: "hologram", notes: nil),
        ])

        drain()

        XCTAssertEqual(try fetchAll().first?.mediaType, .video)
    }

    func testReShareMergesIntoExistingItemInsteadOfDuplicating() throws {
        try enqueue([
            SharedLinkMetadata(url: "https://example.com/post", collection: "", tags: [], mediaType: "bookmark", notes: nil, dateSaved: Date(timeIntervalSinceReferenceDate: 1_000)),
        ])
        drain()

        try enqueue([
            SharedLinkMetadata(url: "https://example.com/post", collection: "Later", tags: ["read"], mediaType: "bookmark", notes: "worth it", dateSaved: Date(timeIntervalSinceReferenceDate: 2_000)),
        ])
        drain()

        let items = try fetchAll()
        XCTAssertEqual(items.count, 1, "re-sharing the same URL must not duplicate")
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.collection, "Later")
        XCTAssertEqual(item.tags, ["read"])
        XCTAssertEqual(item.notes, "worth it")
        XCTAssertEqual(item.dateSaved, Date(timeIntervalSinceReferenceDate: 2_000), "re-share should bump the item to the top")
    }

    func testReShareNeverOverwritesExistingCollection() throws {
        try enqueue([
            SharedLinkMetadata(url: "https://example.com/post", collection: "Original", tags: [], mediaType: "bookmark", notes: nil),
        ])
        drain()

        try enqueue([
            SharedLinkMetadata(url: "https://example.com/post", collection: "Hijack", tags: [], mediaType: "bookmark", notes: nil, dateSaved: Date(timeIntervalSinceNow: 60)),
        ])
        drain()

        XCTAssertEqual(try fetchAll().first?.collection, "Original")
    }

    func testAutoOrganizeFlagIsPropagated() throws {
        try enqueue([
            SharedLinkMetadata(url: "https://example.com/a", collection: "", tags: [], mediaType: "bookmark", notes: nil, autoOrganize: true),
            SharedLinkMetadata(url: "https://example.com/b", collection: "Handpicked", tags: [], mediaType: "bookmark", notes: nil, autoOrganize: true),
            SharedLinkMetadata(url: "https://example.com/c", collection: "", tags: [], mediaType: "bookmark", notes: nil),
        ])

        drain()

        let items = try fetchAll()
        let auto = try XCTUnwrap(items.first { $0.urlString.hasSuffix("/a") })
        XCTAssertTrue(auto.needsAutoCollection)

        let manualCollection = try XCTUnwrap(items.first { $0.urlString.hasSuffix("/b") })
        XCTAssertFalse(manualCollection.needsAutoCollection, "an explicit collection must win over auto-organization")

        let legacyPayload = try XCTUnwrap(items.first { $0.urlString.hasSuffix("/c") })
        XCTAssertFalse(legacyPayload.needsAutoCollection, "payloads without the flag must default to manual")
    }
}

final class CollectionClassifierTests: XCTestCase {
    private func suggest(_ title: String, _ url: String, _ type: MediaType = .bookmark) -> String {
        CollectionClassifier.suggestCollection(title: title, urlString: url, mediaType: type)
    }

    func testKeywordClassification() {
        XCTAssertEqual(suggest("SwiftUI Tutorial for Beginners", "https://youtube.com/watch?v=1", .video), "Educational")
        XCTAssertEqual(suggest("Artist - Song (Official Music Video)", "https://youtube.com/watch?v=2", .video), "Music")
        XCTAssertEqual(suggest("Creamy garlic pasta recipe", "https://example.com/post", .article), "Recipes")
        XCTAssertEqual(suggest("Elden Ring boss gameplay", "https://youtube.com/watch?v=3", .video), "Gaming")
        XCTAssertEqual(suggest("Best exercises for a stronger back workout", "https://example.com", .video), "Fitness")
    }

    func testDomainClassification() {
        XCTAssertEqual(suggest("apple/swift", "https://github.com/apple/swift", .code), "Tech")
        XCTAssertEqual(suggest("Cart", "https://www.amazon.com/dp/B01", .bookmark), "Shopping")
        XCTAssertEqual(suggest("Funny cat", "https://giphy.com/gifs/abc", .image), "Memes")
    }

    func testPlacesAndNewsClassification() {
        XCTAssertEqual(suggest("Blue Bottle Coffee", "https://maps.apple.com/?address=123", .bookmark), "Places")
        XCTAssertEqual(suggest("Directions", "https://www.google.com/maps/place/xyz", .bookmark), "Places")
        XCTAssertEqual(suggest("Senate votes on budget", "https://www.nbcnews.com/politics/article", .article), "News")
        XCTAssertEqual(suggest("Storm hits coast", "https://news.sky.com/story/abc", .article), "News", "host containing 'news' should classify as News")
    }

    func testSingleWordKeywordsRequireWholeWords() {
        // "matching" must not trigger the Sports keyword "match".
        XCTAssertEqual(
            suggest("Feature Matching for Autonomous Self-Driving Vehicles", "https://example.com/paper.pdf", .pdf),
            "Documents"
        )
        // Whole-word "match" still classifies as Sports.
        XCTAssertEqual(suggest("Incredible match highlights", "https://example.com/v", .video), "Sports")
        // Phrase keywords keep working.
        XCTAssertEqual(suggest("How to make pizza dough", "https://youtube.com/watch?v=1", .video), "Recipes")
    }

    func testSpecificRuleBeatsBroadRule() {
        // "how to make" is both recipe-ish and educational — recipes must win.
        XCTAssertEqual(suggest("How to make sourdough bread", "https://youtube.com/watch?v=4", .video), "Recipes")
    }

    func testMediaTypeFallback() {
        XCTAssertEqual(suggest("zzqx", "https://example.com/v", .video), "Videos")
        XCTAssertEqual(suggest("zzqx", "https://example.com/i", .image), "Images")
        XCTAssertEqual(suggest("zzqx", "https://example.com/p", .product), "Shopping")
        XCTAssertEqual(suggest("zzqx", "https://example.com/r", .article), "Reading List")
    }

    func testSocialDomainsClassify() {
        XCTAssertEqual(suggest("Some post", "https://x.com/user/status/123", .bookmark), "Social")
        XCTAssertEqual(suggest("A discussion", "https://www.reddit.com/r/swift/comments/abc", .bookmark), "Social")
    }
}

final class LinkMetadataEnricherTests: XCTestCase {
    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testThumbnailDownscalesLargeImagesPreservingAspect() throws {
        let data = try XCTUnwrap(LinkMetadataEnricher.thumbnailData(from: solidImage(width: 2880, height: 1440)))
        let thumbnail = try XCTUnwrap(UIImage(data: data))

        XCTAssertEqual(max(thumbnail.size.width, thumbnail.size.height), 720, accuracy: 1)
        XCTAssertEqual(thumbnail.size.width / thumbnail.size.height, 2, accuracy: 0.02)
    }

    func testThumbnailLeavesSmallImagesAlone() throws {
        let data = try XCTUnwrap(LinkMetadataEnricher.thumbnailData(from: solidImage(width: 320, height: 200)))
        let thumbnail = try XCTUnwrap(UIImage(data: data))

        XCTAssertEqual(thumbnail.size.width, 320, accuracy: 1)
        XCTAssertEqual(thumbnail.size.height, 200, accuracy: 1)
    }

    func testThumbnailRejectsZeroSizedImage() {
        XCTAssertNil(LinkMetadataEnricher.thumbnailData(from: UIImage()))
    }
}

final class ContentKeywordsTests: XCTestCase {
    func testExtractsDominantNouns() {
        let paragraph = "The sourdough starter needs flour and water. Feed the starter daily; healthy starter makes the bread rise. Mix flour, salt, and water, then fold the dough. Rest the dough, shape the dough, and bake the bread on a stone. Good bread needs patience and a lively starter, plus quality flour."
        let html = "<html><head><script>var x=1;</script></head><body><p>\(paragraph)</p><p>\(paragraph)</p></body></html>"

        let keywords = ContentKeywords.extract(fromHTML: html)
        XCTAssertFalse(keywords.isEmpty)
        XCTAssertTrue(
            Set(keywords).isSubset(of: ["starter", "flour", "bread", "dough", "water"]),
            "unexpected keywords: \(keywords)"
        )
    }

    func testShortOrScriptOnlyPagesYieldNothing() {
        XCTAssertTrue(ContentKeywords.extract(fromHTML: "<p>hi</p>").isEmpty)
        XCTAssertTrue(ContentKeywords.extract(fromHTML: "<script>" + String(repeating: "code();", count: 200) + "</script>").isEmpty)
    }

    func testPlainTextStripsMarkup() {
        let text = ContentKeywords.plainText(fromHTML: "<div>Hello <b>world</b>&nbsp;&amp; friends<style>.x{}</style></div>")
        XCTAssertEqual(text, "Hello world & friends")
    }
}

final class FileTypeInferenceTests: XCTestCase {
    func testMediaTypeFromTypeIdentifier() {
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "com.adobe.pdf"), .pdf)
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "com.compuserve.gif"), .gif)
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "public.jpeg"), .image)
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "public.mpeg-4"), .video)
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "public.mp3"), .audio)
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "public.data"), .document)
        XCTAssertEqual(MediaType.inferred(fromTypeIdentifier: "garbage.nonsense.type"), .document)
    }
}

@MainActor
final class FileImportTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suiteName = "FileImportTests"

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: SavedItem.self, configurations: config)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFileEntryImportsBytesAndCleansInbox() throws {
        let inbox = try XCTUnwrap(AppGroup.fileInboxURL, "test host must have the app group")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let token = "test-\(UUID().uuidString).pdf"
        let bytes = Data("pdf-bytes".utf8)
        try bytes.write(to: inbox.appendingPathComponent(token))

        var metadata = SharedLinkMetadata(url: "", collection: "", tags: [], mediaType: "pdf", notes: nil, autoOrganize: true)
        metadata.fileToken = token
        metadata.originalFileName = "Guitar Manual.pdf"
        defaults.set(try JSONEncoder().encode([metadata]), forKey: AppGroup.sharedLinkQueueKey)

        SharedLinkImporter.drainPendingSharedLinks(into: container.mainContext, defaults: defaults)

        let items = try container.mainContext.fetch(FetchDescriptor<SavedItem>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(item.isFile)
        XCTAssertEqual(item.fileData, bytes)
        XCTAssertEqual(item.title, "Guitar Manual")
        XCTAssertEqual(item.mediaType, .pdf)
        XCTAssertTrue(item.needsAutoCollection)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: inbox.appendingPathComponent(token).path),
            "inbox file must be deleted after a successful import"
        )
    }

    func testMissingInboxFileDropsEntryWithoutCrashing() throws {
        var metadata = SharedLinkMetadata(url: "", collection: "", tags: [], mediaType: "pdf", notes: nil)
        metadata.fileToken = "does-not-exist.pdf"
        defaults.set(try JSONEncoder().encode([metadata]), forKey: AppGroup.sharedLinkQueueKey)

        SharedLinkImporter.drainPendingSharedLinks(into: container.mainContext, defaults: defaults)

        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SavedItem>()).count, 0)
        XCTAssertNil(defaults.data(forKey: AppGroup.sharedLinkQueueKey), "queue must still be cleared")
    }
}

@MainActor
final class SyncDuplicateMergeTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: SavedItem.self, configurations: config)
    }

    func testDuplicatesMergeIntoUserCuratedSurvivor() throws {
        let context = container.mainContext

        let autoItem = SavedItem(title: "example.com", urlString: "https://example.com/a", dateSaved: Date(timeIntervalSinceReferenceDate: 100))
        autoItem.collection = "Reading List"
        autoItem.isFavorite = true
        autoItem.tags = ["one"]

        let userItem = SavedItem(title: "A Nice Page", urlString: "https://example.com/a", dateSaved: Date(timeIntervalSinceReferenceDate: 500))
        userItem.collection = "Handpicked"
        userItem.collectionSetByUser = true
        userItem.tags = ["two"]

        let unrelated = SavedItem(title: "Other", urlString: "https://example.com/b")
        [autoItem, userItem, unrelated].forEach(context.insert)
        try context.save()

        LinkMetadataEnricher.mergeSyncDuplicates(
            in: try context.fetch(FetchDescriptor<SavedItem>()),
            context: context
        )

        let remaining = try context.fetch(FetchDescriptor<SavedItem>())
        XCTAssertEqual(remaining.count, 2)

        let survivor = try XCTUnwrap(remaining.first { $0.urlString.hasSuffix("/a") })
        XCTAssertEqual(survivor.collection, "Handpicked", "user-curated collection must win")
        XCTAssertTrue(survivor.collectionSetByUser)
        XCTAssertTrue(survivor.isFavorite, "favorite from the loser must carry over")
        XCTAssertEqual(survivor.dateSaved, Date(timeIntervalSinceReferenceDate: 100), "earliest save date wins")
        XCTAssertEqual(Set(survivor.tags), ["one", "two"], "tags union")
    }

    func testNoDuplicatesIsANoOp() throws {
        let context = container.mainContext
        context.insert(SavedItem(title: "A", urlString: "https://example.com/a"))
        try context.save()

        LinkMetadataEnricher.mergeSyncDuplicates(
            in: try context.fetch(FetchDescriptor<SavedItem>()),
            context: context
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedItem>()).count, 1)
    }
}

final class OpenGraphScraperTests: XCTestCase {
    private typealias Scraper = LinkMetadataEnricher.OpenGraphScraper

    func testExtractsImageURLBothAttributeOrders() {
        let base = URL(string: "https://shop.example/product/guitar")!
        let html1 = #"<head><meta property="og:image" content="https://cdn.example/guitar.jpg"></head>"#
        XCTAssertEqual(Scraper.imageURL(inHTML: html1, relativeTo: base)?.absoluteString, "https://cdn.example/guitar.jpg")

        let html2 = #"<meta content="/images/g.png" property="og:image">"#
        XCTAssertEqual(Scraper.imageURL(inHTML: html2, relativeTo: base)?.absoluteString, "https://shop.example/images/g.png")
    }

    func testExtractsPriceFromMetaTags() {
        let html = """
        <meta property="og:title" content="Fender Stratocaster">
        <meta property="product:price:amount" content="1099.99">
        <meta property="product:price:currency" content="CAD">
        """
        XCTAssertEqual(Scraper.price(inHTML: html), "CA$1099.99")
    }

    func testExtractsPriceFromJSONLD() {
        let html = #"<script type="application/ld+json">{"@type":"Product","offers":{"price":"499.00","priceCurrency":"USD"}}</script>"#
        XCTAssertEqual(Scraper.price(inHTML: html), "$499.00")
    }

    func testNoPriceReturnsNil() {
        XCTAssertNil(Scraper.price(inHTML: "<head><title>Just a page</title></head>"))
        XCTAssertNil(Scraper.price(inHTML: #"<meta property="product:price:amount" content="TBD">"#), "non-numeric amounts are not prices")
    }
}

final class BubblePackerTests: XCTestCase {
    private let canvas = CGSize(width: 360, height: 480)

    func testBubblesDoNotOverlapAndStayInBounds() {
        let counts = (1...12).map { (name: "C\($0)", count: 13 - $0) }
        let bubbles = BubblePacker.pack(counts: counts, in: canvas)

        XCTAssertGreaterThanOrEqual(bubbles.count, 10, "nearly all bubbles must find a home")
        let bounds = CGRect(origin: .zero, size: canvas)
        for bubble in bubbles {
            XCTAssertTrue(
                bounds.contains(CGRect(x: bubble.center.x - bubble.radius, y: bubble.center.y - bubble.radius,
                                       width: bubble.radius * 2, height: bubble.radius * 2)),
                "\(bubble.name) escapes the canvas"
            )
        }
        for (a, b) in bubbles.flatMap({ a in bubbles.map { (a, $0) } }) where a.name < b.name {
            let distance = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
            XCTAssertGreaterThanOrEqual(distance + 0.5, a.radius + b.radius, "\(a.name) and \(b.name) overlap")
        }
    }

    func testLargestCollectionGetsLargestBubble() {
        let bubbles = BubblePacker.pack(
            counts: [(name: "Big", count: 40), (name: "Small", count: 2)],
            in: canvas
        )
        let big = bubbles.first { $0.name == "Big" }
        let small = bubbles.first { $0.name == "Small" }
        XCTAssertNotNil(big)
        XCTAssertNotNil(small)
        XCTAssertGreaterThan(big!.radius, small!.radius)
    }

    func testDegenerateInputs() {
        XCTAssertTrue(BubblePacker.pack(counts: [], in: canvas).isEmpty)
        XCTAssertTrue(BubblePacker.pack(counts: [(name: "A", count: 1)], in: CGSize(width: 10, height: 10)).isEmpty)
    }
}

final class ThemeCatalogTests: XCTestCase {
    func testEveryThemeResolvesFonts() {
        for choice in ThemeChoice.allCases {
            let spec = ThemeSpec.spec(for: choice)
            // Resolving a Font can't fail, but custom font names can be
            // wrong — round-trip the UIKit names we rely on for nav bars.
            if let name = spec.headingStyle.uiFontName(bold: true) {
                XCTAssertNotNil(UIFont(name: name, size: 17), "\(choice) heading font '\(name)' missing from iOS")
            }
            if let name = spec.bodyStyle.uiFontName(bold: false) {
                XCTAssertNotNil(UIFont(name: name, size: 15), "\(choice) body font '\(name)' missing from iOS")
            }
        }
    }

    func testOnlyClassicIsFree() {
        XCTAssertFalse(ThemeChoice.classic.isProOnly)
        XCTAssertTrue(ThemeChoice.allCases.filter { !$0.isProOnly }.count == 1)
    }
}

final class LinkIntelligenceTests: XCTestCase {
    func testCosineSimilarityBasics() {
        XCTAssertEqual(LinkEmbedder.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 0.0001)
        XCTAssertEqual(LinkEmbedder.cosineSimilarity([1, 2, 3], [1, 2, 3]), 1, accuracy: 0.0001)
        XCTAssertEqual(LinkEmbedder.cosineSimilarity([1, 0], [-1, 0]), -1, accuracy: 0.0001)
        XCTAssertEqual(LinkEmbedder.cosineSimilarity([], []), 0)
        XCTAssertEqual(LinkEmbedder.cosineSimilarity([1, 2], [1, 2, 3]), 0, "mismatched dimensions must not crash")
    }

    func testFloatDataRoundTrip() {
        let vector: [Float] = [0.25, -1.5, 3.75, 0]
        XCTAssertEqual(LinkEmbedder.floats(from: LinkEmbedder.data(from: vector)), vector)
        XCTAssertEqual(LinkEmbedder.floats(from: Data([0x01, 0x02, 0x03])), [], "truncated data must decode to empty")
    }

    func testFilerPicksDominantCollection() {
        let examples = [
            SmartFiler.Example(collection: "Recipes", vector: [1, 0, 0]),
            SmartFiler.Example(collection: "Recipes", vector: [0.95, 0.1, 0]),
            SmartFiler.Example(collection: "Tech", vector: [0, 1, 0]),
        ]
        let verdict = SmartFiler.classify(vector: [0.98, 0.05, 0], examples: examples)
        XCTAssertEqual(verdict?.collection, "Recipes")
    }

    func testFilerRefusesWhenNothingIsClose() {
        let examples = [
            SmartFiler.Example(collection: "Recipes", vector: [1, 0, 0]),
        ]
        XCTAssertNil(
            SmartFiler.classify(vector: [0, 0, 1], examples: examples),
            "an orthogonal link matches nothing the user has filed"
        )
    }

    func testFilerRefusesWithoutDominantWinner() {
        // Two collections in a near-tie: filing would be a coin flip, so
        // the filer must abstain and let the rules classifier decide.
        let examples = [
            SmartFiler.Example(collection: "Recipes", vector: [1, 0.1, 0]),
            SmartFiler.Example(collection: "Food Science", vector: [1, 0.11, 0]),
        ]
        XCTAssertNil(SmartFiler.classify(vector: [1, 0.105, 0], examples: examples))
    }

    func testSentenceEmbeddingSemantics() throws {
        try XCTSkipUnless(LinkEmbedder.isAvailable, "sentence embedding assets unavailable on this runtime")
        let recipe = try XCTUnwrap(LinkEmbedder.vector(for: "creamy garlic pasta recipe"))
        let cooking = try XCTUnwrap(LinkEmbedder.vector(for: "easy weeknight dinner ideas"))
        let racing = try XCTUnwrap(LinkEmbedder.vector(for: "formula 1 qualifying results"))

        XCTAssertGreaterThan(
            LinkEmbedder.cosineSimilarity(recipe, cooking),
            LinkEmbedder.cosineSimilarity(recipe, racing),
            "a recipe should sit closer to cooking than to motorsport"
        )
    }
}

@MainActor
final class CollectionProvenanceTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suiteName = "CollectionProvenanceTests"

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: SavedItem.self, configurations: config)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testManualCollectionMarksUserProvenance() throws {
        let payload = [
            SharedLinkMetadata(url: "https://example.com/manual", collection: "Handpicked", tags: [], mediaType: "bookmark", notes: nil),
            SharedLinkMetadata(url: "https://example.com/auto", collection: "", tags: [], mediaType: "bookmark", notes: nil, autoOrganize: true),
        ]
        defaults.set(try JSONEncoder().encode(payload), forKey: AppGroup.sharedLinkQueueKey)
        SharedLinkImporter.drainPendingSharedLinks(into: container.mainContext, defaults: defaults)

        let items = try container.mainContext.fetch(FetchDescriptor<SavedItem>())
        let manual = try XCTUnwrap(items.first { $0.urlString.hasSuffix("/manual") })
        XCTAssertTrue(manual.collectionSetByUser, "a share-sheet collection choice is user provenance")

        let auto = try XCTUnwrap(items.first { $0.urlString.hasSuffix("/auto") })
        XCTAssertFalse(auto.collectionSetByUser, "auto saves have no user provenance until confirmed")
    }
}

final class MediaTypeInferenceTests: XCTestCase {
    private func inferred(_ urlString: String) -> MediaType {
        MediaType.inferred(from: URL(string: urlString)!)
    }

    func testHostInference() {
        XCTAssertEqual(inferred("https://www.youtube.com/watch?v=abc"), .video)
        XCTAssertEqual(inferred("https://youtu.be/abc"), .video)
        XCTAssertEqual(inferred("https://www.tiktok.com/@user/video/123"), .video)
        XCTAssertEqual(inferred("https://www.amazon.com/dp/B0EXAMPLE"), .product)
        XCTAssertEqual(inferred("https://www.long-mcquade.com/213598/Guitars/Electric"), .product)
        XCTAssertEqual(inferred("https://anystore.example/products/blue-guitar"), .product)
        XCTAssertEqual(inferred("https://github.com/apple/swift"), .code)
        XCTAssertEqual(inferred("https://open.spotify.com/track/abc"), .audio)
        XCTAssertEqual(inferred("https://myblog.substack.com/p/post"), .article)
    }

    func testInstagramSplitsByPath() {
        XCTAssertEqual(inferred("https://www.instagram.com/reel/abc"), .video)
        XCTAssertEqual(inferred("https://www.instagram.com/p/abc"), .image)
    }

    func testFileExtensionBeatsHost() {
        XCTAssertEqual(inferred("https://example.com/paper.pdf"), .pdf)
        XCTAssertEqual(inferred("https://example.com/photo.JPG"), .image)
        XCTAssertEqual(inferred("https://example.com/clip.mp4"), .video)
    }

    func testGIFInference() {
        XCTAssertEqual(inferred("https://media.tenor.com/abc/dance.gif"), .gif)
        XCTAssertEqual(inferred("https://tenor.com/view/funny-cat-123"), .gif)
        XCTAssertEqual(inferred("https://giphy.com/gifs/excited-abc"), .gif)
    }

    func testLookalikeHostsDoNotMatch() {
        XCTAssertEqual(inferred("https://notyoutube.com/watch"), .bookmark)
        XCTAssertEqual(inferred("https://example.com"), .bookmark)
    }
}
