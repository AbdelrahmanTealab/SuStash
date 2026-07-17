//
//  LinkIntelligence.swift
//  SuStash
//
//  On-device semantic understanding of saved links: sentence embeddings
//  (NaturalLanguage), similarity math, and the personal auto-filer that
//  learns from the user's own filing decisions. Nothing leaves the device.
//

import Foundation
import NaturalLanguage
import SwiftData

// MARK: - Embeddings

enum LinkEmbedder {
    /// Apple's on-device sentence embedding. English-centric — when the
    /// model or the text doesn't produce a vector, callers fall back to
    /// rules/substring behavior.
    private static let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    static var isAvailable: Bool {
        sentenceEmbedding != nil
    }

    static func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let vector = sentenceEmbedding?.vector(for: trimmed.lowercased()) else { return nil }
        return vector.map(Float.init)
    }

    /// The text an item is embedded from. Host and tags sharpen the signal
    /// when titles are short ("Home", "Watch").
    static func embeddingText(title: String, host: String, tags: [String]) -> String {
        ([title, host] + tags).joined(separator: " ")
    }

    // MARK: Codec (Float32, little-endian — stable across devices)

    static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floats(from data: Data) -> [Float] {
        guard data.count % MemoryLayout<Float>.stride == 0 else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        let denominator = (normA * normB).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }
}

// MARK: - Personal auto-filer

/// Files new links the way the user files theirs: k-nearest-neighbors over
/// the embeddings of manually-filed items. Conservative by design — when
/// confidence is low it returns nil and the rules classifier takes over.
enum SmartFiler {
    struct Example {
        let collection: String
        let vector: [Float]
    }

    struct Verdict: Equatable {
        let collection: String
        let confidence: Float
    }

    /// Minimum similarity for the single best neighbor — below this the
    /// user has simply never filed anything like this link.
    static let minimumBestSimilarity: Float = 0.60
    /// Neighbors below this don't get a vote.
    static let voteFloor: Float = 0.45
    /// The winning collection must own this share of the neighbor vote.
    static let minimumVoteShare: Float = 0.55

    static func classify(vector: [Float], examples: [Example], k: Int = 5) -> Verdict? {
        guard !examples.isEmpty, !vector.isEmpty else { return nil }

        let neighbors = examples
            .map { (collection: $0.collection, similarity: LinkEmbedder.cosineSimilarity($0.vector, vector)) }
            .sorted { $0.similarity > $1.similarity }
            .prefix(k)

        guard let best = neighbors.first, best.similarity >= minimumBestSimilarity else { return nil }

        var votes: [String: Float] = [:]
        for neighbor in neighbors where neighbor.similarity >= voteFloor {
            votes[neighbor.collection, default: 0] += neighbor.similarity
        }
        guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }

        let totalVotes = votes.values.reduce(0, +)
        let share = totalVotes > 0 ? winner.value / totalVotes : 0
        guard share >= minimumVoteShare else { return nil }

        return Verdict(collection: winner.key, confidence: best.similarity * share)
    }

    /// Convenience over the library: examples are items the user filed
    /// (or confirmed) personally.
    @MainActor
    static func classifyAgainstLibrary(vector: [Float], in context: ModelContext) -> Verdict? {
        // embeddingData is externalStorage and can't appear in a #Predicate;
        // filter it in memory below.
        let descriptor = FetchDescriptor<SavedItem>(
            predicate: #Predicate { $0.collectionSetByUser && $0.collection != nil }
        )
        guard let manualItems = try? context.fetch(descriptor), !manualItems.isEmpty else { return nil }

        let examples = manualItems.compactMap { item -> Example? in
            guard let collection = item.collection, let data = item.embeddingData else { return nil }
            let vector = LinkEmbedder.floats(from: data)
            guard !vector.isEmpty else { return nil }
            return Example(collection: collection, vector: vector)
        }
        return classify(vector: vector, examples: examples)
    }

    /// Top semantically similar items to an anchor vector, most similar first.
    static func similarItems(
        to anchorVector: [Float],
        among candidates: [SavedItem],
        minimumSimilarity: Float = 0.50,
        limit: Int = 5
    ) -> [SavedItem] {
        candidates
            .compactMap { item -> (SavedItem, Float)? in
                guard let data = item.embeddingData else { return nil }
                let vector = LinkEmbedder.floats(from: data)
                guard !vector.isEmpty else { return nil }
                let similarity = LinkEmbedder.cosineSimilarity(anchorVector, vector)
                return similarity >= minimumSimilarity ? (item, similarity) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
