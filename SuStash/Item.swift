//
//  Item.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
