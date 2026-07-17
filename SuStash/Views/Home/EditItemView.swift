//
//  EditItemView.swift
//  SuStash
//
//  Edit a saved link's details or move it to another collection. Changes
//  are staged locally and written only on Save.
//

import SwiftUI
import SwiftData

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [SavedItem]

    let item: SavedItem

    @State private var title: String
    @State private var collection: String
    @State private var tags: String
    @State private var mediaType: MediaType
    @State private var notes: String
    @State private var isFavorite: Bool

    init(item: SavedItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _collection = State(initialValue: item.collection ?? "")
        _tags = State(initialValue: item.tags.joined(separator: ", "))
        _mediaType = State(initialValue: item.mediaType)
        _notes = State(initialValue: item.notes ?? "")
        _isFavorite = State(initialValue: item.isFavorite)
    }

    private var existingCollections: [String] {
        Array(Set(allItems.compactMap(\.collection))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Collection") {
                    HStack {
                        TextField("None", text: $collection)
                            .textInputAutocapitalization(.words)
                        if !existingCollections.isEmpty {
                            Menu {
                                ForEach(existingCollections, id: \.self) { name in
                                    Button(name) { collection = name }
                                }
                                if !collection.isEmpty {
                                    Divider()
                                    Button("Remove from collection", role: .destructive) {
                                        collection = ""
                                    }
                                }
                            } label: {
                                Image(systemName: "folder")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }

                Section("Tags (comma-separated)") {
                    TextField("e.g. ios, design", text: $tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Type") {
                    Picker("Type", selection: $mediaType) {
                        ForEach(MediaType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle(isOn: $isFavorite) {
                        Label("Favorite", systemImage: "star")
                    }
                }

                if let url = item.url {
                    Section("Link") {
                        Text(url.absoluteString)
                            .font(AppTheme.captionFont(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .navigationTitle("Edit Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        withAnimation(.snappy) {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                item.title = trimmedTitle
            }
            let trimmedCollection = collection.trimmingCharacters(in: .whitespacesAndNewlines)
            let newCollection = trimmedCollection.isEmpty ? nil : trimmedCollection
            if newCollection != item.collection {
                // An explicit choice in the editor is a filing decision the
                // personal auto-filer should learn from.
                item.collectionSetByUser = newCollection != nil
            }
            item.collection = newCollection
            item.tags = tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            item.mediaType = mediaType
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            item.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            item.isFavorite = isFavorite

            // Title or tags may have changed — refresh the embedding so
            // smart features track the edit.
            let text = LinkEmbedder.embeddingText(title: item.title, host: item.host, tags: item.tags)
            if let vector = LinkEmbedder.vector(for: text) {
                item.embeddingData = LinkEmbedder.data(from: vector)
            }
            try? modelContext.save()
        }
        dismiss()
    }
}
