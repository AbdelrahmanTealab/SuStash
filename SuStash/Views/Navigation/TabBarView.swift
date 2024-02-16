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

            RecommendsView()
                .tabItem {
                    Label("Recommends", systemImage: "star.fill")
                }

            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "tray.full.fill")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}
