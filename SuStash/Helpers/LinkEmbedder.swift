//
//  LinkEmbedder.swift
//  SuStash
//
//  On-device sentence embeddings (NaturalLanguage framework) for saved
//  links. Powers Smart Filing, semantic search, and Rediscover suggestions.
//  Nothing leaves the device.
//

import Foundation
import NaturalLanguage

enum LinkEmbedder {
    /// Bump when the embedding input format or model changes — items with an
    /// older revision get re-embedded by the enricher's backfill pass.
    static let revision = 1

    private static let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    /// Sentence embeddings are English-centric; when the asset is missing
    /// (rare) or the text defeats it, callers fall back to rules.
    static var isAvailable: Bool {
        sentenceEmbedding != nil
    }

    static func embed(_ text: String) -> [Float]? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !cleaned.isEmpty,
              let vector = sentenceEmbedding?.vector(for: cleaned) else { return nil }
        return vector.map(Float.init)
    }

    /// The canonical text embedded for a saved item. Host and tags give the
    /// vector signal even when a title is just a hostname.
    static func embeddingText(title: String, host: String, tags: [String]) -> String {
        ([title, host] + tags).joined(separator: " ")
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            magA += a[index] * a[index]
            magB += b[index] * b[index]
        }
        let denominator = (magA * magB).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }
}
