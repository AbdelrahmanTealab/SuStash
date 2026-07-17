//
//  SettingsView.swift
//  SuStash
//

import CloudKit
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [SavedItem]

    @AppStorage(AppSettings.tapBehaviorKey, store: AppSettings.store) private var tapBehaviorRaw = TapBehavior.openLink.rawValue
    @AppStorage(AppGroup.preferredShareSaveModeKey, store: AppSettings.store) private var saveModeRaw = "auto"
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearanceRaw = AppearanceOverride.system.rawValue
    @State private var themeManager = ThemeManager.shared
    @AppStorage(SharedStore.syncEnabledKey, store: AppSettings.store) private var syncEnabled = false

    @State private var proStore = ProStore.shared
    @State private var showPaywall = false
    @AppStorage(RediscoverReminder.enabledKey, store: AppSettings.store) private var reminderEnabled = false
    @State private var showNotificationsDeniedAlert = false
    @State private var iCloudStatus: String = "Checking iCloud…"
    @State private var showDeleteConfirmation = false
    @State private var exportURL: URL?
    @State private var showExportSheet = false

    private var uncategorizedCount: Int {
        allItems.filter { $0.collection == nil }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                profileSection

                Section("Saving") {
                    Picker(selection: $saveModeRaw) {
                        Text("Auto — organized for you").tag("auto")
                        Text("Manual — you pick").tag("manual")
                    } label: {
                        Label("Default save mode", systemImage: "wand.and.stars")
                    }

                    Picker(selection: $tapBehaviorRaw) {
                        ForEach(TapBehavior.allCases) { behavior in
                            Text(behavior.label).tag(behavior.rawValue)
                        }
                    } label: {
                        Label("Tap behavior", systemImage: "hand.tap")
                    }
                }

                Section {
                    Toggle(isOn: reminderBinding) {
                        Label("Weekly Rediscover reminder", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("One gentle nudge on Sundays about links you saved but never opened. Nothing else, ever.")
                }

                Section {
                    Picker(selection: $appearanceRaw) {
                        ForEach(AppearanceOverride.allCases) { override in
                            Text(override.label).tag(override.rawValue)
                        }
                    } label: {
                        Label("Light / Dark", systemImage: "circle.lefthalf.filled")
                    }

                    themePickerRow
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Each theme brings its own colors, fonts, and a subtle ambient background.")
                }

                Section("Organize") {
                    Button {
                        organizeUncategorized()
                    } label: {
                        Label("Auto-organize uncategorized links", systemImage: "sparkles.rectangle.stack")
                    }
                    .disabled(uncategorizedCount == 0)

                    if uncategorizedCount > 0 {
                        Text("^[\(uncategorizedCount) link](inflect: true) without a collection")
                            .font(AppTheme.captionFont(13))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    LabeledContent {
                        Text("\(allItems.count)")
                    } label: {
                        Label("Saved links", systemImage: "tray.full")
                    }

                    Button {
                        if proStore.isPro {
                            exportLinks()
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        HStack {
                            Label("Export all links", systemImage: "square.and.arrow.up")
                            Spacer()
                            if !proStore.isPro { proBadge }
                        }
                    }
                    .disabled(allItems.isEmpty)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                    .disabled(allItems.isEmpty)
                }

                Section {
                } footer: {
                    Text("SuStash \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .font(AppTheme.captionFont(12))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete all saved links? This can't be undone.",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive, action: deleteAll)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showExportSheet) {
                if let exportURL {
                    ActivityView(items: [exportURL])
                        .presentationDetents([.medium, .large])
                }
            }
            .task(checkICloud)
            .alert("Notifications are off", isPresented: $showNotificationsDeniedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable notifications for SuStash in the Settings app to get the weekly reminder.")
            }
        }
    }

    /// Toggle that requests permission on first enable and reverts if denied.
    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { reminderEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        if await RediscoverReminder.requestAuthorization() {
                            reminderEnabled = true
                            RediscoverReminder.refreshSchedule(
                                enabled: true,
                                unopenedCount: allItems.filter { $0.lastOpenedAt == nil }.count
                            )
                        } else {
                            reminderEnabled = false
                            showNotificationsDeniedAlert = true
                        }
                    }
                } else {
                    reminderEnabled = false
                    RediscoverReminder.refreshSchedule(enabled: false, unopenedCount: 0)
                }
            }
        )
    }

    private var proSection: some View {
        Section {
            if proStore.isPro {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text("SuStash Pro")
                        .font(AppTheme.headingFont(16))
                    Spacer()
                    Text("Active")
                        .font(AppTheme.captionFont(13))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Upgrade to SuStash Pro")
                                .font(AppTheme.headingFont(16))
                            Text("Smart filing, sync, themes, export")
                                .font(AppTheme.captionFont(13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: iCloudStatus == "Signed in to iCloud" ? "checkmark.icloud.fill" : "icloud.slash")
                    .foregroundStyle(iCloudStatus == "Signed in to iCloud" ? AppTheme.accent : .secondary)
                Text(iCloudStatus)
                    .font(AppTheme.bodyFont(15))
            }

            if proStore.isPro {
                Toggle(isOn: $syncEnabled) {
                    Label("iCloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label("iCloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                        Spacer()
                        proBadge
                    }
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            if proStore.isPro {
                Text("Sync changes take effect the next time SuStash launches.")
            }
        }
    }

    private var proBadge: some View {
        Text("PRO")
            .font(AppTheme.headingFont(10))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.accent.gradient, in: Capsule())
    }

    private var themePickerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Theme", systemImage: "paintpalette")
                Spacer()
                if !proStore.isPro { proBadge }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemeChoice.allCases) { choice in
                        themeCard(choice)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func themeCard(_ choice: ThemeChoice) -> some View {
        let spec = ThemeSpec.spec(for: choice)
        let isSelected = themeManager.choice == choice

        return Button {
            if choice.isProOnly && !proStore.isPro {
                showPaywall = true
            } else {
                withAnimation(.snappy) {
                    themeManager.choice = choice
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(spec.background)
                        .frame(width: 72, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(spec.accent).frame(width: 34, height: 5)
                        Capsule().fill(spec.card).frame(width: 46, height: 5)
                        Capsule().fill(spec.card).frame(width: 40, height: 5)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? spec.accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
                Text(choice.displayName)
                    .font(spec.headingStyle.font(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(spec.accent) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    @Sendable
    private func checkICloud() async {
        let status = try? await CKContainer.default().accountStatus()
        iCloudStatus = switch status {
        case .available: "Signed in to iCloud"
        case .noAccount: "Not signed in to iCloud"
        case .restricted: "iCloud is restricted"
        default: "iCloud unavailable"
        }
    }

    private func organizeUncategorized() {
        withAnimation(.snappy) {
            for item in allItems where item.collection == nil {
                item.collection = CollectionClassifier.suggestCollection(
                    title: item.title,
                    urlString: item.urlString,
                    mediaType: item.mediaType
                )
            }
            try? modelContext.save()
        }
    }

    private func exportLinks() {
        struct ExportedLink: Encodable {
            let url: String
            let title: String
            let collection: String?
            let tags: [String]
            let notes: String?
            let dateSaved: Date
        }

        let payload = allItems.map {
            ExportedLink(
                url: $0.urlString, title: $0.title, collection: $0.collection,
                tags: $0.tags, notes: $0.notes, dateSaved: $0.dateSaved
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuStash-links.json")
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
        exportURL = fileURL
        showExportSheet = true
    }

    private func deleteAll() {
        SpotlightIndexer.removeAll()
        withAnimation(.snappy) {
            allItems.forEach(modelContext.delete)
            try? modelContext.save()
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: SavedItem.self, inMemory: true)
}
