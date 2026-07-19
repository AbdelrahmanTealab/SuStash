//
//  SharedStore.swift
//  SuStash
//
//  SwiftData container in the app group, plus the importer that drains
//  links queued by the share extension.
//

import CoreData
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.atealab.SuStash", category: "SharedStore")

enum SharedStore {
    static let cloudKitContainerID = "iCloud.com.atealab.SuStash"
    static let syncEnabledKey = "iCloudSyncEnabled"

    /// Stable accessor — routes to the holder so the container can be
    /// rebuilt live when the sync setting changes.
    @MainActor
    static var container: ModelContainer {
        StoreHolder.shared.container
    }

    /// Whether the store should mirror to CloudKit. Only the main app runs
    /// the mirroring (extensions and widgets read locally), and only when
    /// the user has turned sync on.
    private static var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
        let isAppProcess = Bundle.main.bundleURL.pathExtension != "appex"
        let syncEnabled = UserDefaults(suiteName: AppGroup.identifier)?
            .bool(forKey: syncEnabledKey) ?? false
        // Explicit on both branches: with the iCloud entitlement present,
        // the default (.automatic) would silently enable sync everywhere.
        return (isAppProcess && syncEnabled) ? .private(cloudKitContainerID) : .none
    }

    /// Store lives in the app group container so the extension can read it in
    /// the future (e.g. to list existing collections). Falls back to the app's
    /// own container, then to in-memory, rather than crash at launch — the
    /// fallbacks only trigger on misconfiguration, and both are logged as faults.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedItem.self])

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) {
            let storeURL = groupURL.appendingPathComponent("SuStash.sqlite")
            do {
                let config = ModelConfiguration(
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: cloudKitDatabase
                )
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                logger.fault("App group store unavailable, falling back: \(error)")
            }
        } else {
            logger.fault("App group container missing — check the \(AppGroup.identifier) entitlement")
        }

        do {
            return try ModelContainer(for: schema)
        } catch {
            logger.fault("Default store unavailable, using in-memory store: \(error)")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // In-memory container creation has no failure modes at runtime.
            return try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
    }
}

/// Owns the live ModelContainer so toggling iCloud Sync takes effect
/// immediately — the container is rebuilt and the view tree re-roots on
/// `generation` instead of requiring an app relaunch (which on macOS users
/// rarely do: closing the window doesn't quit the process).
@MainActor
@Observable
final class StoreHolder {
    static let shared = StoreHolder()

    private(set) var container: ModelContainer
    private(set) var generation = 0

    private init() {
        container = SharedStore.makeContainer()
    }

    func rebuildForSyncChange() {
        try? container.mainContext.save()
        container = SharedStore.makeContainer()
        generation += 1
        logger.notice("Store container rebuilt (generation \(self.generation)) for sync setting change")
    }
}

/// Surfaces CloudKit mirroring activity — most importantly its FAILURES,
/// which are otherwise completely silent (e.g. a schema that was never
/// deployed to the Production environment). SwiftData's sync runs on
/// NSPersistentCloudKitContainer underneath, which posts these events.
@MainActor
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    private(set) var statusText: String = "Waiting for first sync…"
    private(set) var lastErrorText: String?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated {
                self?.record(event)
            }
        }
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        let phase = switch event.type {
        case .setup: "Setting up"
        case .import: "Downloading"
        case .export: "Uploading"
        @unknown default: "Syncing"
        }

        if let error = event.error {
            lastErrorText = error.localizedDescription
            statusText = "\(phase) failed"
            logger.error("CloudKit \(phase) failed: \(error)")
        } else if event.endDate != nil {
            lastErrorText = nil
            statusText = "Synced"
        } else {
            statusText = "\(phase)…"
        }
    }
}

enum SharedLinkImporter {
    /// Moves queued shared links into the store. The queue is cleared only
    /// after a successful save, so a crash mid-import never loses links;
    /// dedupe below makes the retry safe.
    @MainActor
    static func drainPendingSharedLinks(
        into context: ModelContext,
        defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)
    ) {
        guard let defaults, let data = defaults.data(forKey: AppGroup.sharedLinkQueueKey) else { return }

        guard let pending = try? JSONDecoder().decode([SharedLinkMetadata].self, from: data),
              !pending.isEmpty else {
            // Undecodable data would wedge the queue forever; discard it.
            logger.error("Discarding unreadable shared-link queue (\(data.count) bytes)")
            defaults.removeObject(forKey: AppGroup.sharedLinkQueueKey)
            return
        }

        // One item per URL: re-sharing a saved link merges into the existing
        // item (bumps it to the top, fills in missing details) instead of
        // duplicating. Also makes crash-retry drains idempotent.
        let existing = (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
        var byURL: [String: SavedItem] = [:]
        for item in existing where byURL[item.urlString] == nil {
            byURL[item.urlString] = item
        }

        var changedCount = 0
        var consumedFileTokens: [String] = []
        for metadata in pending {
            // File saves: bytes are waiting in the app-group inbox.
            if let token = metadata.fileToken {
                guard let item = makeFileItem(from: metadata, token: token) else {
                    // Inbox file missing (cancelled/cleaned) — drop the entry.
                    logger.error("Skipping file save with missing inbox token")
                    continue
                }
                context.insert(item)
                consumedFileTokens.append(token)
                changedCount += 1
                continue
            }

            if let existingItem = byURL[metadata.url] {
                if merge(metadata, into: existingItem) {
                    changedCount += 1
                }
                continue
            }
            guard let item = makeSavedItem(from: metadata) else {
                logger.error("Skipping shared link with invalid URL: \(metadata.url, privacy: .private)")
                continue
            }
            context.insert(item)
            byURL[item.urlString] = item
            changedCount += 1
        }

        do {
            if changedCount > 0 {
                try context.save()
            }
            defaults.removeObject(forKey: AppGroup.sharedLinkQueueKey)
            // Inbox bytes are deleted only after the save landed — a crash
            // before this point retries cleanly from the intact queue.
            if let inbox = AppGroup.fileInboxURL {
                for token in consumedFileTokens {
                    try? FileManager.default.removeItem(at: inbox.appendingPathComponent(token))
                }
            }
            logger.info("Imported or merged \(changedCount) shared item(s)")
        } catch {
            // Keep the queue; the next foreground pass retries.
            context.rollback()
            logger.error("Failed to save imported links, will retry: \(error)")
        }
    }

    /// Builds a file-backed item from an inbox token. Returns nil when the
    /// staged file no longer exists.
    @MainActor
    private static func makeFileItem(from metadata: SharedLinkMetadata, token: String) -> SavedItem? {
        guard let inbox = AppGroup.fileInboxURL else { return nil }
        let fileURL = inbox.appendingPathComponent(token)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty,
              data.count <= AppGroup.maxSavedFileBytes else { return nil }

        let fileName = metadata.originalFileName ?? token
        let title = (fileName as NSString).deletingPathExtension

        let collection = metadata.collection.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = metadata.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = metadata.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let item = SavedItem(
            title: title.isEmpty ? fileName : title,
            urlString: "",
            mediaType: MediaType(rawValue: metadata.mediaType) ?? .document,
            collection: collection.isEmpty ? nil : collection,
            tags: tags,
            notes: notes.isEmpty ? nil : notes,
            dateSaved: metadata.dateSaved
        )
        item.fileData = data
        item.fileName = fileName
        item.needsAutoCollection = (metadata.autoOrganize ?? false) && item.collection == nil
        item.collectionSetByUser = item.collection != nil
        return item
    }

    /// Fold a re-shared link into its existing item. Returns false when the
    /// payload adds nothing (the crash-retry case), so callers can skip saving.
    private static func merge(_ metadata: SharedLinkMetadata, into item: SavedItem) -> Bool {
        var changed = false

        if metadata.dateSaved > item.dateSaved {
            item.dateSaved = metadata.dateSaved
            changed = true
        }

        let collection = metadata.collection.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.collection == nil {
            if !collection.isEmpty {
                item.collection = collection
                item.collectionSetByUser = true
                changed = true
            } else if metadata.autoOrganize ?? false, !item.needsAutoCollection {
                item.needsAutoCollection = true
                changed = true
            }
        }

        let newTags = metadata.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !item.tags.contains($0) }
        if !newTags.isEmpty {
            item.tags.append(contentsOf: newTags)
            changed = true
        }

        if item.notes == nil,
           let notes = metadata.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            item.notes = notes
            changed = true
        }

        return changed
    }

    private static func makeSavedItem(from metadata: SharedLinkMetadata) -> SavedItem? {
        guard let url = URL(string: metadata.url) else { return nil }

        let mediaType = MediaType(rawValue: metadata.mediaType) ?? .inferred(from: url)
        let collection = metadata.collection.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = metadata.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = metadata.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let item = SavedItem(
            title: url.host ?? metadata.url,
            urlString: metadata.url,
            mediaType: mediaType,
            collection: collection.isEmpty ? nil : collection,
            tags: tags,
            notes: notes.isEmpty ? nil : notes,
            dateSaved: metadata.dateSaved
        )
        if item.title.hasPrefix("www.") {
            item.title = String(item.title.dropFirst(4))
        }
        // A manually chosen collection always wins over auto-organization,
        // and doubles as a training example for the personal auto-filer.
        item.needsAutoCollection = (metadata.autoOrganize ?? false) && item.collection == nil
        item.collectionSetByUser = item.collection != nil
        return item
    }
}
