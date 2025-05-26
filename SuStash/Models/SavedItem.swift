//
//  SavedItem.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-18.
//

import Foundation
import SwiftUI

struct SavedItem: Identifiable {
    let id: UUID = UUID()
    var title: String
    var url: URL
    var mediaType: MediaType?
    var collection: String?
    var tags: [String]

    var sourceApp: String? // e.g., "Safari", "Reddit"
    var previewImageURL: URL? // for visual bookmark previews
    var isFavorite: Bool = false
    var dateSaved: Date = Date()
    var notes: String? // user-added comments or highlights
    var estimatedReadingTime: Int? // in minutes, based on word count
    var reminderDate: Date? // for job deadlines, revisit nudges, etc.
    var isSharedPublicly: Bool = false // for public collections

    enum MediaType: String, Codable {
      case article
      case video
      case image
      case audio
      case pdf
      case document
      case code
      case tweet
      case thread
      case bookmark
      case unknown
    }
}
