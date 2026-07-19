//
//  MessagesViewController.swift
//  SuStashMessages
//
//  The iMessage app: recent saves in a grid with search, one tap to drop
//  a link (or file) into the conversation.
//

import Messages
import SwiftData
import SwiftUI
import UIKit

class MessagesViewController: MSMessagesAppViewController {
    private var hostingController: UIHostingController<MessagesPickerView>?

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        embedPicker()
    }

    private func embedPicker() {
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let picker = MessagesPickerView(
            onPick: { [weak self] pick in self?.insert(pick) },
            onWantsExpanded: { [weak self] in self?.requestPresentationStyle(.expanded) }
        )
        let hosting = UIHostingController(rootView: picker)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
    }

    fileprivate func insert(_ pick: MessagePick) {
        guard let conversation = activeConversation else { return }
        switch pick {
        case .link(let urlString):
            conversation.insertText(urlString)
        case .file(let tempURL, let name):
            conversation.insertAttachment(tempURL, withAlternateFilename: name)
        }
        requestPresentationStyle(.compact)
    }
}

enum MessagePick {
    case link(String)
    case file(URL, String)
}

// MARK: - Picker UI

struct MessagesPickerView: View {
    var onPick: (MessagePick) -> Void
    var onWantsExpanded: () -> Void

    // The extension is its own process: one local, non-syncing container.
    private static let container = SharedStore.makeContainer()

    @State private var searchText = ""
    @State private var items: [SavedItem] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search your stash…", text: $searchText)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .onChange(of: searchFocused) { _, focused in
                        if focused { onWantsExpanded() }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(items.isEmpty ? "Nothing saved yet" : "No matches")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(filtered) { item in
                            MessageTile(item: item)
                                .onTapGesture { pick(item) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear(perform: reload)
    }

    private var filtered: [SavedItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.host.localizedCaseInsensitiveContains(query)
                || (item.collection?.localizedCaseInsensitiveContains(query) ?? false)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func reload() {
        var descriptor = FetchDescriptor<SavedItem>(
            sortBy: [SortDescriptor(\.dateSaved, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        let context = ModelContext(Self.container)
        items = (try? context.fetch(descriptor)) ?? []
    }

    private func pick(_ item: SavedItem) {
        if item.isFile {
            guard let data = item.fileData else { return }
            let name = item.fileName ?? "\(item.title).dat"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("msg-\(UUID().uuidString)-\(name)")
            guard (try? data.write(to: url)) != nil else { return }
            onPick(.file(url, name))
        } else if !item.urlString.isEmpty {
            onPick(.link(item.urlString))
        }
    }
}

private struct MessageTile: View {
    let item: SavedItem

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let data = item.previewImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(AppTheme.badgeColor(for: item.mediaType).gradient)
                        .overlay(
                            Image(systemName: item.mediaType.systemImage)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.9))
                        )
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(item.title)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
