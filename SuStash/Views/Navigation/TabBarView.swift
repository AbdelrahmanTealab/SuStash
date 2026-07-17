//
//  TabBarView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import SwiftUI

struct TabBarView: View {
    enum Tab: String {
        case home
        case library
        case rediscover
    }

    @State private var selection: Tab

    init() {
        // Testability hook: `-initialTab library` as a launch argument lands
        // in UserDefaults.standard automatically. Absent in normal launches.
        let initial = UserDefaults.standard.string(forKey: "initialTab").flatMap(Tab.init(rawValue:))
        _selection = State(initialValue: initial ?? .home)
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)
            CollectionsView()
                // Rebuild on theme switch so their navigation bars pick up
                // the new appearance fonts; Home stays alive because the
                // Settings sheet (where switching happens) hangs off it.
                .id(ThemeManager.shared.choice)
                .tabItem {
                    Label("Library", systemImage: "square.grid.2x2.fill")
                }
                .tag(Tab.library)
            RecommendsView()
                .id(ThemeManager.shared.choice)
                .tabItem {
                    Label("Rediscover", systemImage: "sparkles")
                }
                .tag(Tab.rediscover)
        }
        .tint(AppTheme.accent)
    }
}

#Preview {
    TabBarView()
        .modelContainer(for: SavedItem.self, inMemory: true)
}
