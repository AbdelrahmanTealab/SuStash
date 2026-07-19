//
//  SavedItemCellView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-18.
//

import QuickLook
import SwiftUI
import SwiftData
import UIKit

// MARK: - Shared interactions

/// Tap (honoring the user's tap-behavior setting), context menu with Edit,
/// and the share sheet. Applied to list rows and media-grid tiles alike so
/// every representation of a link behaves the same.
struct SavedItemInteractions: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let item: SavedItem
    @State private var showEdit = false
    @State private var showShareSheet = false
    @State private var filePreviewURL: URL?

    func body(content: Content) -> some View {
        let base = content
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)

        return Group {
            if let notes = item.notes, !notes.isEmpty {
                // Long-press shows the saved note as a speech-bubble preview
                // above the menu — the one place notes get read.
                base.contextMenu {
                    menuItems
                } preview: {
                    NotesBubbleView(item: item, notes: notes)
                }
            } else {
                base.contextMenu { menuItems }
            }
        }
            .sheet(isPresented: $showEdit) {
                EditItemView(item: item)
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareTarget = item.isFile ? item.writeTemporaryFile() : item.url {
                    ActivityView(items: [shareTarget])
                        .presentationDetents([.medium, .large])
                }
            }
            // System QuickLook presentation: full native chrome — share sheet
            // with Save Image / Save to Files, markup, pinch-zoom, and video
            // playback controls. (An embedded QLPreviewController loses most
            // of that chrome.)
            .quickLookPreview($filePreviewURL)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            showEdit = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        if let collection = item.collection, !item.collectionSetByUser {
            // Confirming an auto-filed collection turns it into a training
            // example for the personal filer.
            Button {
                withAnimation(.snappy) {
                    item.collectionSetByUser = true
                    try? modelContext.save()
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Keep in “\(collection)”", systemImage: "checkmark.circle")
            }
        }
        Button {
            copyLink()
        } label: {
            Label(item.isFile ? "Copy" : "Copy Link", systemImage: "doc.on.doc")
        }
        if item.isFile {
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else if let url = item.url {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Button(action: toggleFavorite) {
            Label(
                item.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: item.isFavorite ? "star.slash" : "star"
            )
        }
        Divider()
        Button(role: .destructive, action: delete) {
            Label("Delete", systemImage: "trash")
        }
    }

    private func handleTap() {
        switch AppSettings.tapBehavior {
        case .openLink:
            if item.isFile {
                guard let url = item.writeTemporaryFile() else { return }
                item.lastOpenedAt = Date()
                try? modelContext.save()
                filePreviewURL = url
            } else {
                guard let url = item.url else { return }
                item.lastOpenedAt = Date()
                try? modelContext.save()
                openURL(url)
            }
        case .copyLink:
            copyLink()
        case .shareLink:
            showShareSheet = true
        }
    }

    private func copyLink() {
        if item.isFile {
            // Copy the content itself where the pasteboard understands it.
            if let data = item.fileData, item.mediaType == .image || item.mediaType == .gif,
               let image = UIImage(data: data) {
                UIPasteboard.general.image = image
            } else if let url = item.writeTemporaryFile() {
                UIPasteboard.general.setItemProviders([NSItemProvider(contentsOf: url)].compactMap { $0 }, localOnly: false, expirationDate: nil)
            }
        } else {
            UIPasteboard.general.url = item.url
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func delete() {
        SpotlightIndexer.remove(urlString: item.urlString)
        withAnimation(.snappy) {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    private func toggleFavorite() {
        withAnimation(.snappy) {
            item.isFavorite.toggle()
            try? modelContext.save()
        }
    }
}

extension View {
    func savedItemInteractions(_ item: SavedItem) -> some View {
        modifier(SavedItemInteractions(item: item))
    }
}

/// Speech-bubble note card shown as the context-menu preview.
struct NotesBubbleView: View {
    let item: SavedItem
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Text(item.title)
                    .font(AppTheme.headingFont(14))
                    .lineLimit(1)
            }

            Text(notes)
                .font(AppTheme.bodyFont(15))
                .lineSpacing(3)

            Text(item.host)
                .font(AppTheme.captionFont(12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(AppTheme.card)
    }
}

extension SavedItem {
    /// Writes the file bytes to a temp path (named for QuickLook/share) and
    /// returns its URL. Cheap enough to redo per use; tmp is system-cleaned.
    func writeTemporaryFile() -> URL? {
        guard let data = fileData else { return nil }
        let name = fileName ?? "\(title).dat"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sustash-\(abs(name.hashValue))-\(name)")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard (try? data.write(to: url)) != nil else { return nil }
        }
        return url
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Row

/// A saved-link row with interactions plus list-only swipe actions.
struct SavedItemRow: View {
    @Environment(\.modelContext) private var modelContext

    let item: SavedItem

    var body: some View {
        SavedItemCellView(item: item)
            .savedItemInteractions(item)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    SpotlightIndexer.remove(urlString: item.urlString)
                    withAnimation(.snappy) {
                        modelContext.delete(item)
                        try? modelContext.save()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    withAnimation(.snappy) {
                        item.isFavorite.toggle()
                        try? modelContext.save()
                    }
                } label: {
                    Label(
                        item.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: item.isFavorite ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
    }
}

// MARK: - Cell

struct SavedItemCellView: View {
    let item: SavedItem

    private var isVisualMedia: Bool {
        (item.mediaType == .image || item.mediaType == .gif)
            && (item.animatedPreviewData != nil || item.previewImageData != nil)
    }

    var body: some View {
        if isVisualMedia {
            visualCell
        } else {
            standardCell
        }
    }

    // Full-width media banner for images and GIFs (GIFs animate in place).
    private var visualCell: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .overlay(mediaPreview)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.headingFont(15))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.displaySubtitle)
                    if let collection = item.collection {
                        Text("·  \(collection)")
                    }
                }
                .font(AppTheme.captionFont(12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                if item.mediaType == .gif {
                    Text("GIF")
                        .font(AppTheme.headingFont(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            .padding(8)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let gifData = item.animatedPreviewData {
            AnimatedImageView(data: gifData)
        } else if let data = item.previewImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    private var standardCell: some View {
        HStack(spacing: 12) {
            mediaBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AppTheme.bodyFont(16))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.displaySubtitle)
                        .lineLimit(1)

                    if let price = item.productPrice {
                        Text(price)
                            .font(AppTheme.headingFont(11))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.13), in: Capsule())
                            .lineLimit(1)
                    }

                    if let collection = item.collection {
                        HStack(spacing: 3) {
                            if !item.collectionSetByUser {
                                // Auto-filed — long-press offers "Keep in …".
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                            }
                            Text(collection)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .lineLimit(1)
                    }

                    Text(item.dateSaved, format: .relative(presentation: .named))
                        .layoutPriority(-1)
                }
                // Wide theme fonts (mono, typewriter) squeeze this row;
                // truncate rather than wrap into vertical columns.
                .lineLimit(1)
                .font(AppTheme.captionFont(12))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var mediaBadge: some View {
        if let data = item.previewImageData, let thumbnail = UIImage(data: data) {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: item.mediaType.systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(badgeColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(3)
                }
                .transition(.opacity)
        } else {
            Image(systemName: item.mediaType.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(badgeColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var badgeColor: Color {
        AppTheme.badgeColor(for: item.mediaType)
    }
}

#Preview {
    List {
        SavedItemCellView(item: SavedItem(
            title: "youtube.com",
            urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            mediaType: .video,
            collection: "Watch Later"
        ))
        SavedItemCellView(item: SavedItem(
            title: "swift.org",
            urlString: "https://swift.org/blog",
            mediaType: .article
        ))
    }
    .listStyle(.plain)
}
