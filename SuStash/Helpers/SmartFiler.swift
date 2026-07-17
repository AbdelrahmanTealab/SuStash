//
//  SmartFiler.swift
//  SuStash
//
//  Personal auto-filing: a weighted k-nearest-neighbors vote over the
//  user's own manual filing decisions, in embedding space. Pro feature —
//  callers gate on entitlement; this type just does the math.
//

import Foundation

enum SmartFiler {
    /// Below this many manual examples the classifier abstains — rules
    /// handle cold start better than three data points would.
    static let minimumExamples = 8
    /// Nearest neighbor must be at least this similar or we abstain.
    static let confidenceThreshold: Float = 0.7
    private static let neighborCount = 5

    struct Suggestion: Equatable {
        let collection: String
        let confidence: Float
    }

    /// Training example: one manually-filed link.
    struct Example {
        let collection: String
        let embedding: [Float]
    }

    static func suggestCollection(for embedding: [Float], from examples: [Example]) -> Suggestion? {
        guard examples.count >= minimumExamples else { return nil }

        let neighbors = examples
            .map { (collection: $0.collection, similarity: LinkEmbedder.cosineSimilarity(embedding, $0.embedding)) }
            .sorted { $0.similarity > $1.similarity }
            .prefix(neighborCount)

        guard let nearest = neighbors.first, nearest.similarity >= confidenceThreshold else { return nil }

        // Similarity-weighted vote so one very close neighbor beats three
        // mediocre ones from another collection.
        var votes: [String: Float] = [:]
        for neighbor in neighbors where neighbor.similarity > 0 {
            votes[neighbor.collection, default: 0] += neighbor.similarity
        }
        guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }

        return Suggestion(collection: winner.key, confidence: nearest.similarity)
    }

    /// Extracts training examples from the library: only links the user
    /// filed personally count as ground truth.
    static func examples(from items: [SavedItem]) -> [Example] {
        items.compactMap { item in
            guard item.collectionSetByUser,
                  let collection = item.collection,
                  let embedding = item.embedding else { return nil }
            return Example(collection: collection, embedding: embedding)
        }
    }
}
