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

    enum MediaType {
        case article, video, image
    }
}
