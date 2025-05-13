//
//  SavedItemCellView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-18.
//

import Foundation
import SwiftUI
import LinkPresentation

struct SavedItemCellView: View {
    var item: SavedItem

    var body: some View {
        HStack {
            AsyncImage(url: item.url)
                .scaledToFit()
                .frame(width: 50, height: 50)
                .cornerRadius(8)
                .overlay(
                    item.mediaType == .video ? Image(systemName: "play.circle").foregroundColor(.white) : nil
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.url.host ?? item.url.absoluteString)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
    }
}
