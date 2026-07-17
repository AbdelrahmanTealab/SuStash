//
//  CollectionClassifier.swift
//  SuStash
//
//  On-device, rule-based auto-categorization for "Auto" saves. Runs after
//  metadata enrichment so the real page title is available. Deterministic
//  and offline by design; a Foundation Models pass can replace `classify`
//  later without touching callers.
//

import Foundation

enum CollectionClassifier {
    /// Ordered rules — first match wins, so the more specific categories
    /// (Recipes, Memes) sit above the broad ones (Educational, Tech).
    private static let rules: [(collection: String, keywords: [String])] = [
        ("Places", ["maps.apple.com", "maps.app.goo", "goo.gl/maps", "google.com/maps", "waze.com", "openstreetmap", "what3words", "plus.codes", "foursquare"]),
        ("Recipes", ["recipe", "recipes", "cooking", "baking", "ingredients", "allrecipes", "food52", "seriouseats", "tasty.co", "how to make", "air fryer", "one pot"]),
        ("Memes", ["meme", "memes", "9gag", "imgflip", "knowyourmeme", "shitpost", "giphy.com", "tenor.com"]),
        ("Social", ["twitter.com", "x.com/", "t.co/", "reddit.com", "facebook.com", "threads.net", "news.ycombinator"]),
        ("Gaming", ["gameplay", "walkthrough", "speedrun", "gaming", "twitch.tv", "ign.com", "gamespot", "minecraft", "fortnite", "elden ring", "nintendo", "playstation", "xbox", "steam"]),
        ("Music", ["official video", "official music video", "official audio", "lyrics", "music video", "album", "remix", "spotify.com", "soundcloud", "music.apple", "bandcamp", "feat.", "ft."]),
        ("Fitness", ["workout", "exercise", "gym", "yoga", "pilates", "protein", "hypertrophy", "cardio", "stretching"]),
        ("Educational", ["tutorial", "how to", "learn", "lesson", "course", "lecture", "explained", "guide", "khanacademy", "coursera", "udemy", "edx", "documentary", "crash course"]),
        ("Sports", ["highlights", "espn", "premier league", "champions league", "nba", "nfl", "fifa", "match", "world cup", "formula 1", "f1.com"]),
        ("News", ["breaking", "bbc.c", "cnn.com", "reuters", "nytimes", "theguardian", "aljazeera", "apnews", "bloomberg", "nbcnews", "foxnews", "cbsnews", "abcnews", "washingtonpost", "wsj.com", "usatoday", "npr.org", "axios.com", "politico", "cnbc.com", "newsweek", "time.com/", "dailymail", "telegraph.co", "independent.co"]),
        ("Tech", ["github.com", "stackoverflow", "programming", "developer", "javascript", "python", "swiftui", "swift ", "api ", "techcrunch", "theverge", "arstechnica", "hacker news", "ycombinator"]),
        ("Travel", ["travel", "itinerary", "things to do", "airbnb", "booking.com", "tripadvisor", "lonelyplanet", "visit "]),
        ("Shopping", ["amazon.", "ebay.", "etsy.", "aliexpress", "temu.com", "wishlist", "deal", "discount"]),
        ("Movies & TV", ["trailer", "netflix", "imdb", "episode", "season ", "rotten tomatoes", "letterboxd", "hbo"]),
        ("Art & Design", ["dribbble", "behance", "figma", "design", "illustration", "typography", "pinterest.com"]),
        ("Podcasts", ["podcast", "podcasts.apple", "episode #"]),
    ]

    /// Suggest a collection name from what we know about a link.
    /// Falls back to a media-type shelf so Auto saves always land somewhere
    /// sensible rather than in an "Uncategorized" bucket.
    static func suggestCollection(title: String, urlString: String, mediaType: MediaType) -> String {
        let haystack = (title + " " + urlString).lowercased()

        for rule in rules where rule.keywords.contains(where: { haystack.contains($0) }) {
            return rule.collection
        }

        // Outlets we don't list explicitly almost always carry "news" in the
        // host (nbcnews.com, news.sky.com, …). Host only — titles are too noisy.
        if let host = URL(string: urlString)?.host?.lowercased(), host.contains("news") {
            return "News"
        }

        switch mediaType {
        case .video: return "Videos"
        case .image: return "Images"
        case .gif: return "GIFs"
        case .audio: return "Music"
        case .pdf, .document: return "Documents"
        case .code: return "Tech"
        case .product: return "Shopping"
        case .article, .bookmark: return "Reading List"
        }
    }
}
