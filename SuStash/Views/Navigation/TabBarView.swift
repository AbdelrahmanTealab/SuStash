//
//  TabBarView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import SwiftUI

struct TabBarView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "tray.full.fill")
                }
            RecommendsView()
                .tabItem {
                    Label("Recommends", systemImage: "star.fill")
                }

        }
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}
