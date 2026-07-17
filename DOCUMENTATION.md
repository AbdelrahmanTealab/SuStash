# SuStash — Architecture & Wiring Documentation

SuStash saves, organizes, and resurfaces links shared from anywhere on iOS. Everything runs
on-device: no servers, no third-party SDKs, no analytics. The only network calls fetch link
metadata (titles, thumbnails, GIFs, prices) from the pages the user saved, and optional
iCloud sync goes through the user's own private CloudKit database.

---

## 1. Targets

| Target | What it is | Key entry point |
|---|---|---|
| **SuStash** | The main SwiftUI app | `SuStash/SuStashApp.swift` |
| **SuStashShareExtension** | The share-sheet extension ("Save to SuStash") | `SuStashShareExtension/ShareViewController.swift` |
| **SuStashWidgets** | Home-screen widgets (Recent Saves + configurable Collection) | `SuStashWidgets/SuStashWidgets.swift` |
| **SuStashTests** | Unit tests (hosted in the app) | `SuStashTests/SuStashTests.swift` |

All three product targets share the **app group** `group.com.atealab.SuStash` (UserDefaults +
files) — that's how they exchange data. Files compiled into more than one target:

- `SuStash/Models/SharedLinkMetadata.swift` → app + extension (the queue payload, `MediaType`, `AppGroup` keys)
- `SuStash/Models/SavedItem.swift`, `Helpers/SharedStore.swift`, `Helpers/Theme.swift` → app + widgets

Rule of thumb: anything compiled into the extension or widgets must not reference app-only
types (ProStore, classifiers, views).

---

## 2. The data model

`SavedItem` (SwiftData `@Model`, `SuStash/Models/SavedItem.swift`) — one saved link:

| Field | Purpose |
|---|---|
| `title`, `urlString` | Display title (enriched later) and the canonical URL string. `url`/`host`/`sourceName` are computed. |
| `mediaTypeRaw` | Raw string so adding enum cases never migrates the schema; `mediaType` accessor falls back to `.bookmark` for unknown/legacy raws (e.g. removed `tweet`/`thread`). |
| `collection` | Plain string (no Collection entity — groups are derived by query). |
| `collectionSetByUser` | **Provenance flag**: true when the user chose/confirmed the collection. These items are the training set for the personal auto-filer. |
| `needsAutoCollection` | Set by the importer for "Auto" saves; cleared once a collection is assigned post-enrichment. |
| `tags` | `[String]`, set manually in the share sheet / editor. |
| `previewImageData` | Downscaled JPEG thumbnail (≤720px, `externalStorage`). |
| `animatedPreviewData` | Full GIF data for `.gif` items (≤12 MB, `externalStorage`); previewImageData holds a static first frame. |
| `embeddingData` | Sentence embedding of title+host+tags as a Float32 buffer (~2 KB). Powers smart filing, suggestions, semantic search. |
| `productPrice` | Display string ("CA$69.00") scraped from product pages. |
| `enrichmentAttempted` | One-shot flag so dead links aren't refetched every launch. |
| `isFavorite`, `lastOpenedAt`, `notes`, `dateSaved` | UX state. `lastOpenedAt` drives Rediscover. |

**CloudKit-compatibility rules baked in**: every property has a default or is optional, no
unique constraints. Do not add `@Attribute(.unique)` or you'll break sync.

⚠️ **Hard-won lesson**: SwiftData `#Predicate` **cannot reference `externalStorage`
attributes** (`embeddingData`, image data). The fetch throws, and a `try?` turns that into a
silent no-op. Predicate only on flags/strings; filter blob-nil-ness in memory.

---

## 3. The save pipeline (the heart of the app)

```
Share sheet (any app)
  └─ ShareViewController: extract URL (public.url → plain-text data detector)
      └─ ShareInputView: Auto / Manual radio
          Auto   → payload { url, autoOrganize: true }
          Manual → payload { url, collection, tags, mediaType, notes }
            └─ append SharedLinkMetadata JSON to app-group UserDefaults queue
               key: "sharedLinkItems"  (+ synchronize() — extension dies instantly)

Main app: runLibraryPipeline()  ← fires from BOTH root .task (cold launch)
  │                                AND scenePhase == .active (returns to foreground)
  ├─ 1. SharedLinkImporter.drainPendingSharedLinks   (SharedStore.swift)
  │      • decode queue; undecodable data is discarded (never wedges)
  │      • one item per URL: re-shares MERGE into the existing item
  │        (bump date, fill missing collection/tags/notes) instead of duplicating
  │      • queue cleared ONLY after a successful save (crash-safe, idempotent)
  ├─ 2. LinkMetadataEnricher.enrichPendingItems       (LinkMetadataEnricher.swift)
  │      per item, sequential, saves incrementally:
  │      • LPMetadataProvider → real title + preview image
  │      • GIFs: download animated data (direct .gif or via image provider), 12 MB cap
  │      • OpenGraphScraper fallback: og:image whenever LinkPresentation has no
  │        image; product price from product:price:amount / JSON-LD for .product
  │      • compute sentence embedding (NLEmbedding, English) → embeddingData
  │      • autoOrganizeIfNeeded:
  │          Pro → SmartFiler k-NN over user-filed items (confident? use it)
  │          else / abstained → CollectionClassifier rules → media-type shelf
  └─ 3. syncDerivedState (SuStashApp.swift)
         • SpotlightIndexer.reindex (Core Spotlight)
         • WidgetCenter.reloadAllTimelines
         • mirror collection names → app-group "knownCollections"
           (the share extension's suggestion chips read this)
```

⚠️ **Hard-won lesson**: never gate cold-launch work on `scenePhase == .active` alone. A
system alert (permissions, Apple Account verification) holds the scene at `.inactive`
indefinitely — the pipeline also runs from the root `.task` for exactly this reason.

### Classification (CollectionClassifier.swift)
Ordered keyword/domain rules, first match wins (Places, Recipes, Memes, Social, Gaming,
Music, Fitness, Educational, Sports, News, Tech, Travel, Shopping, Movies & TV, Art & Design,
Podcasts) → host-contains-"news" heuristic → media-type shelf (Videos, Images, GIFs→Memes,
Music, Documents, Tech, Shopping, Reading List).

### Personal auto-filer (LinkIntelligence.swift, Pro)
`SmartFiler.classify` = k-nearest-neighbors (k=5, cosine similarity) over embeddings of
items where `collectionSetByUser == true`. Deliberately conservative: best neighbor ≥ 0.60,
sub-0.45 neighbors don't vote, winner needs ≥ 55% of the weighted vote — otherwise it
abstains and the rules run. Training examples come from: manual share-sheet choices, Edit
sheet moves, and the "Keep in …" confirmation on the context menu (auto-filed items show a
sparkle on their collection chip until confirmed).

---

## 4. The main app UI

```
SuStashApp
 └─ SplashScreenView → AuthenticationView-free! → TabBarView
     ├─ HomeView (custom header, no nav stack)
     │    • filter menu: Recents / Favorites / sources / tags (ranked by count)
     │    • view modes: list / grid / icons (persisted, app-group "homeViewMode")
     │    • search: substring matches first, then semantic (embedding) matches
     │    • paste-to-save (+), Settings gear (sheet)
     ├─ CollectionsView "Library" (NavigationStack)
     │    • segments: Collections (card grid) / Tags (list) / Media (photo grid)
     │    • statistics toggle (toolbar): bubbles / bar chart / donut
     │    • context menu: rename, delete (cascades items, confirms at view level*)
     └─ RecommendsView "Rediscover" (NavigationStack)
          • "Because you saved …" (Pro): unopened links ≥0.62 similar to the
            last opened/favorited item — hidden rather than weak
          • Still unopened (seeded shuffle) / Favorites / From the vault
```

Every representation of a link (row, grid card, icon tile, media tile, Rediscover card) gets
`.savedItemInteractions(item)` (SavedItemCellView.swift): tap honors the **tap behavior**
setting (open/copy/share), long-press = context menu (+ **notes speech-bubble preview** when
the item has notes), Edit sheet, share sheet. Rows add swipe actions on top.

⚠️ *SwiftUI gotcha: dialogs can't be presented from buttons inside a context menu (the menu
dismisses and takes the button's identity with it). Dialog state lives on the owning view —
see `collectionPendingDelete` in CollectionsView.*

`EditItemView` writes user provenance (`collectionSetByUser`) on collection changes and
recomputes the embedding when the title/tags change.

---

## 5. Theme system (Theme.swift)

- `ThemeChoice` (8): Classic (free) + Cotton Candy, Cyberpunk, Retro, Neon, Ocean, Forest,
  Mono (Pro). Each `ThemeSpec` = dynamic light/dark colors (accent/background/card) +
  `ThemeFontStyle` pair (heading/body; custom iOS fonts or system rounded/serif/mono
  designs) + `ThemeLinePattern`.
- **Live switching**: `ThemeManager` is `@Observable`; every `AppTheme.*` accessor routes
  through `ThemeManager.shared.choice`, so any view body that reads theme values re-renders
  instantly when the choice changes. Persisted to app-group key `"appTheme"` (widgets read
  the same key). Nav-bar fonts use a UIKit appearance proxy, reapplied on switch; Library
  and Rediscover carry `.id(theme)` in TabBarView so their bars rebuild (Home must NOT —
  the Settings sheet hangs off it).
- `ThemedScreenBackground` = background color + `AmbientLinesCanvas`: a Canvas in a
  TimelineView (~12 fps) drawing a few 1-pt paths at ~5% opacity with 45–75 s drift periods.
  Pattern per theme (grid/waves/scanlines/beams/curves); honors Reduce Motion (static).
- ⚠️ Wide fonts (mono/typewriter) squeeze caption rows — keep `.lineLimit(1)` on metadata lines.

## 6. Pro / StoreKit (ProStore.swift, PaywallView.swift)

- Products: `com.atealab.SuStash.pro.monthly` / `.yearly` / `.lifetime` (StoreKit 2).
  `SuStash.storekit` config enables free local testing (select it in the scheme's Run
  options). **The same three IDs must be created in App Store Connect before release.**
- `ProStore.shared` (@Observable): entitlement state (`isPro`, cached in defaults so Pro
  doesn't flicker offline), transaction-updates listener, purchase/restore.
- **Gates**: personal auto-filer, "Because you saved…" suggestions, iCloud sync toggle,
  non-Classic themes, JSON export. Free forever: saving, rules-based Auto, search
  (including semantic), widgets, Spotlight.
- Debug: launch argument `-pro` fakes the entitlement (Debug builds only).

## 7. iCloud sync (SharedStore.swift)

SwiftData store lives in the app-group container (`SuStash.sqlite`). When the user enables
sync (Pro) the container is built with `cloudKitDatabase: .private("iCloud.com.atealab.SuStash")`
— **explicitly `.none` otherwise**, because with the iCloud entitlement present the
`.automatic` default would silently sync for everyone. Only the app process mirrors;
extension/widgets read locally. Toggling takes effect on next launch (container is built once).
Fallback chain on failure: app-group store → local store → in-memory (never crash at launch;
each fallback logs a `.fault`).

## 8. Widgets, Spotlight, deep links

- Widgets read the shared store directly (no CloudKit). Rows deep-link
  `sustash://open?u=<encoded>`; `SuStashApp.handleDeepLink` records `lastOpenedAt` then
  opens the real URL. Spotlight taps arrive via `CSSearchableItemActionType` with the
  urlString as identifier.
- `SpotlightIndexer` reindexes everything after each pipeline pass (title, notes, tags,
  collection, thumbnail); deletes remove entries.

## 9. Settings & app-group keys

| Key (app group) | Meaning |
|---|---|
| `sharedLinkItems` | The share-extension queue (JSON `[SharedLinkMetadata]`) |
| `preferredShareSaveMode` | "auto" / "manual" — share sheet default, editable in Settings |
| `knownCollections` | Collection names mirrored for the extension's chips |
| `tapBehavior` | openLink / copyLink / shareLink |
| `appearanceOverride` | system / light / dark |
| `appTheme` | ThemeChoice raw value |
| `homeViewMode` | list / grid / icons |
| `iCloudSyncEnabled` | Pro sync toggle (read at container creation) |
| `isProCached` | Last verified entitlement (offline continuity) |

`UserDefaults.standard` (launch-arg hooks, Debug conveniences): `initialTab`
(home/library/rediscover), `libraryStats`, `-pro`.

## 10. Testing & build notes

- ~42 unit tests: importer transactionality/merging, classifier rules, media inference,
  OpenGraph parsing, thumbnail downscaling, SmartFiler thresholds, cosine/codec math,
  bubble packing, theme font resolution. Embedding-dependent tests `XCTSkip` when the
  NL assets are unavailable.
- Build/test: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project
  SuStash.xcodeproj -scheme SuStash -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test`
- The pbxproj mixes classic file references (app target) with filesystem-synchronized
  groups (extension, widgets). New app-target files must be registered manually; extension/
  widget folders pick up files automatically.
- Enricher logs at `.notice` (persisted) — `log show --predicate 'subsystem ==
  "com.atealab.SuStash"'` is the first debugging stop.
