//
//  SharedLinkMetadata.swift
//  SuStash
//
//  Compiled into BOTH the app and the share extension targets.
//  Must not import SwiftData or reference app-only types.
//

import Foundation
import UniformTypeIdentifiers

enum AppGroup {
    static let identifier = "group.com.atealab.SuStash"
    static let sharedLinkQueueKey = "sharedLinkItems"
    static let preferredShareSaveModeKey = "preferredShareSaveMode"

    /// Files shared through the extension are streamed here (never held in
    /// the extension's memory); the app consumes and deletes them on import.
    static let fileInboxDirectoryName = "FileInbox"
    /// Hard cap for saved files. Above this we refuse rather than bloat the
    /// store (and CloudKit sync) with data SwiftData must load to display.
    static let maxSavedFileBytes = 50_000_000

    static var fileInboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(fileInboxDirectoryName, isDirectory: true)
    }
    static let knownCollectionsKey = "knownCollections"
}

/// The kinds of content SuStash can save.
// Legacy raw values ("tweet", "thread") no longer have cases; SavedItem's
// accessor falls back to .bookmark for them, no migration needed.
enum MediaType: String, Codable, CaseIterable {
    case article
    case video
    case image
    case gif
    case audio
    case pdf
    case document
    case code
    case product
    case bookmark

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .gif: "GIF"
        default: rawValue.capitalized
        }
    }

    var systemImage: String {
        switch self {
        case .article: "newspaper"
        case .video: "play.rectangle.fill"
        case .image: "photo"
        case .gif: "photo.stack"
        case .audio: "waveform"
        case .pdf: "doc.text"
        case .document: "doc"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .product: "bag"
        case .bookmark: "bookmark"
        }
    }

    /// Type for a saved file, from its uniform type identifier. Used instead
    /// of a picker — a file's type is a fact, not a choice.
    static func inferred(fromTypeIdentifier identifier: String) -> MediaType {
        guard let type = UTType(identifier) else { return .document }
        if type.conforms(to: .gif) { return .gif }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .audio) { return .audio }
        return .document
    }

    /// Best-guess type for a URL. File extension wins over host, since a
    /// direct file link is more specific than the site serving it.
    static func inferred(from url: URL) -> MediaType {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "gif": return .gif
        case "jpg", "jpeg", "png", "webp", "heic", "svg": return .image
        case "mp4", "mov", "m4v", "webm": return .video
        case "mp3", "m4a", "wav", "aac", "ogg", "flac": return .audio
        default: break
        }

        guard let host = url.host?.lowercased() else { return .bookmark }

        func matches(_ domains: String...) -> Bool {
            domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        if matches("youtube.com", "youtu.be", "vimeo.com", "tiktok.com", "twitch.tv", "dailymotion.com") {
            return .video
        }
        if matches("instagram.com") {
            let path = url.path.lowercased()
            return (path.hasPrefix("/reel") || path.hasPrefix("/tv")) ? .video : .image
        }
        if matches("github.com", "gitlab.com", "stackoverflow.com") { return .code }
        if matches(
            "amazon.com", "amazon.ca", "amazon.co.uk", "ebay.com", "etsy.com",
            "aliexpress.com", "temu.com", "walmart.com", "bestbuy.com", "target.com",
            "newegg.com", "wayfair.com", "ikea.com", "long-mcquade.com", "sweetwater.com",
            "thomann.de", "shopify.com", "myshopify.com"
        ) {
            return .product
        }
        // Storefront path conventions on any host: /product/…, /dp/… (Amazon-style)
        let path = url.path.lowercased()
        if path.contains("/product/") || path.contains("/products/") || path.hasPrefix("/dp/") || path.contains("/itm/") {
            return .product
        }
        if matches("spotify.com", "soundcloud.com", "music.apple.com", "podcasts.apple.com") { return .audio }
        if matches("giphy.com", "tenor.com") { return .gif }
        if matches("pinterest.com", "imgur.com", "flickr.com") { return .image }
        if matches("medium.com", "substack.com") { return .article }

        return .bookmark
    }
}

/// Payload the share extension appends to a queue in app group UserDefaults.
/// The main app drains the queue into its SwiftData store on foreground.
/// `mediaType` stays a raw String so an unknown future value can never
/// fail decoding and wedge the queue.
struct SharedLinkMetadata: Codable {
    var url: String
    var collection: String
    var tags: [String]
    var mediaType: String
    var notes: String?
    var dateSaved: Date = Date()
    // Optional so payloads queued by older extension builds still decode.
    var autoOrganize: Bool? = nil
    // File saves: `url` is "" and these point at a file in the app-group
    // inbox. Optional keeps old payloads decodable.
    var fileToken: String? = nil
    var originalFileName: String? = nil
}
