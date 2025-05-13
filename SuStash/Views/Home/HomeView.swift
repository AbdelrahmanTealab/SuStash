//
//  HomeView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import Foundation
import SwiftUI

struct HomeView: View {
    @StateObject var viewModel = HomeViewModel()
    
    var body: some View {
        ScrollView {
            Text("Recents")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.leading)
            if viewModel.savedItems.isEmpty {
                // Display a message when the list is empty
                Text("No items saved yet.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Continue with existing code
                ForEach(viewModel.savedItems) { item in
                    LinkPreview(url: item.url)
                        .frame(width: 300, height: 200)
                        .cornerRadius(10)
                }
            }
        }
    }
}


struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
