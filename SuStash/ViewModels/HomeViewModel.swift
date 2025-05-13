//
//  HomeViewModel.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-18.
//

import Foundation

class HomeViewModel: ObservableObject {
    @Published var savedItems: [SavedItem] = []
    
    init() {
        loadItems()
    }

    // Load items, fetch data, etc.
    func loadItems(){
        savedItems.append(
            SavedItem(
                title: "How to Use Custom Fonts in SwiftUI",
                url: URL(string:"https://www.youtube.com/watch?v=4PI04Yj3Ngs")!
                )
        )
    }
}
