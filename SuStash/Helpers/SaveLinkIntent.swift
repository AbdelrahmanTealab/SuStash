//
//  SaveLinkIntent.swift
//  SuStash
//
//  Shortcuts / Action-button support: "Save Link to SuStash". Inserts
//  directly into the shared store; enrichment and auto-filing run on the
//  next app foreground, exactly like a share-extension save.
//

import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct SaveLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Link to SuStash"
    static let description = IntentDescription(
        "Saves a link to your stash. It gets a title, preview, and collection automatically."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Link")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SharedStore.container.mainContext
        let urlString = url.absoluteString

        let descriptor = FetchDescriptor<SavedItem>(predicate: #Predicate { $0.urlString == urlString })
        if (try? context.fetch(descriptor).first) != nil {
            return .result(dialog: "That link is already in your stash.")
        }

        let item = SavedItem(
            title: url.host ?? urlString,
            urlString: urlString,
            mediaType: .inferred(from: url)
        )
        item.needsAutoCollection = true
        context.insert(item)
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "Saved to SuStash.")
    }
}

struct SuStashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveLinkIntent(),
            phrases: [
                "Save a link to \(.applicationName)",
                "Stash this in \(.applicationName)",
            ],
            shortTitle: "Save Link",
            systemImageName: "bookmark.fill"
        )
    }
}
