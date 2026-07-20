//
//  SuStashApp.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import CoreSpotlight
import SwiftData
import SwiftUI
import WidgetKit

@main
struct SuStashApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearanceRaw = AppearanceOverride.system.rawValue
    init() {
        ThemeManager.applyNavigationBarFonts(for: ThemeManager.shared.choice)
    }

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                // Re-root the tree when the container is rebuilt (sync
                // toggled): @Query views bind to the new container and the
                // root .task refires the pipeline.
                .id(StoreHolder.shared.generation)
                .tint(AppTheme.accent)
                .preferredColorScheme(
                    (AppearanceOverride(rawValue: appearanceRaw) ?? .system).colorScheme
                )
                .onOpenURL(perform: handleDeepLink)
                .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlightResult)
                .task {
                    ProStore.shared.start()
                    _ = SyncMonitor.shared  // start observing before first sync event
                    #if DEBUG
                    // `-rebuildStoreAfterLaunch`: exercises the container
                    // re-root with live views, for headless crash testing.
                    if ProcessInfo.processInfo.arguments.contains("-rebuildStoreAfterLaunch") {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            StoreHolder.shared.rebuildForSyncChange()
                        }
                    }
                    #endif
                    // Cold-launch pass, independent of scenePhase: a system
                    // alert (permissions, Apple Account) can hold the scene
                    // at .inactive indefinitely, and saved links must import
                    // regardless.
                    runLibraryPipeline()
                }
        }
        .modelContainer(SharedStore.container)
        .onChange(of: scenePhase) { _, phase in
            // Re-runs on every return from the share sheet, so freshly
            // shared links appear the moment the app is visible.
            guard phase == .active else { return }
            runLibraryPipeline()
        }
    }

    /// Import queued shares, enrich, then refresh everything derived from
    /// the library. Safe to call repeatedly — every stage is idempotent.
    private func runLibraryPipeline() {
        withAnimation(.snappy) {
            SharedLinkImporter.drainPendingSharedLinks(into: SharedStore.container.mainContext)
        }
        Task {
            await LinkMetadataEnricher.enrichPendingItems(in: SharedStore.container.mainContext)
            await syncDerivedState()
        }
    }

    /// sustash://open?u=<percent-encoded link> — used by widget rows.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sustash" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let encoded = components?.queryItems?.first(where: { $0.name == "u" })?.value,
              let target = URL(string: encoded) else { return }
        openSavedLink(urlString: target.absoluteString)
    }

    private func handleSpotlightResult(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        openSavedLink(urlString: identifier)
    }

    @MainActor
    private func openSavedLink(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let context = SharedStore.container.mainContext
        let descriptor = FetchDescriptor<SavedItem>(predicate: #Predicate { $0.urlString == urlString })
        if let item = try? context.fetch(descriptor).first {
            item.lastOpenedAt = Date()
            try? context.save()
        }
        openURL(url)
    }

    /// Everything downstream of the library changing: Spotlight, widgets,
    /// and the collection names the share extension offers as suggestions.
    @MainActor
    private func syncDerivedState() async {
        let context = SharedStore.container.mainContext
        guard let items = try? context.fetch(FetchDescriptor<SavedItem>()) else { return }

        SpotlightIndexer.reindex(items)
        WidgetCenter.shared.reloadAllTimelines()

        let collections = Array(Set(items.compactMap(\.collection))).sorted()
        AppSettings.store.set(collections, forKey: AppGroup.knownCollectionsKey)

        RediscoverReminder.refreshSchedule(
            enabled: AppSettings.store.bool(forKey: RediscoverReminder.enabledKey),
            unopenedCount: items.filter { $0.lastOpenedAt == nil }.count
        )
    }
}
