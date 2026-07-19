//
//  SaveComposerView.swift
//  SuStash
//
//  The Auto/Manual save sheet, shared by the share extension and the
//  in-app + button. Links get the full manual form; files inherit their
//  type from the file itself, so the Type picker is hidden for them.
//

import SwiftUI

enum ShareSaveMode: String {
  case auto
  case manual
}

/// What is being saved.
enum ComposerInput {
  case url(URL)
  /// `oversized` files show the form disabled with an explanation.
  case file(displayName: String, mediaType: MediaType, oversized: Bool)

  var mediaType: MediaType {
    switch self {
    case .url(let url): .inferred(from: url)
    case .file(_, let type, _): type
    }
  }

  var isFile: Bool {
    if case .file = self { return true }
    return false
  }
}

struct SaveComposerView: View {
  let input: ComposerInput
  var onSave: (SharedLinkMetadata) -> Void
  var onCancel: () -> Void

  @State private var mode: ShareSaveMode
  @State private var collection: String = ""
  @State private var tags: String = ""
  @State private var mediaType: MediaType
  @State private var notes: String = ""
  @State private var didSubmit = false

  private static let groupDefaults = UserDefaults(suiteName: AppGroup.identifier)

  /// Collection names mirrored by the main app on each foreground pass.
  private let knownCollections: [String]

  private var isOversized: Bool {
    if case .file(_, _, true) = input { return true }
    return false
  }

  init(input: ComposerInput, onSave: @escaping (SharedLinkMetadata) -> Void, onCancel: @escaping () -> Void) {
    self.input = input
    self.onSave = onSave
    self.onCancel = onCancel
    _mediaType = State(initialValue: input.mediaType)

    let saved = Self.groupDefaults?.string(forKey: AppGroup.preferredShareSaveModeKey)
    _mode = State(initialValue: saved.flatMap(ShareSaveMode.init(rawValue:)) ?? .auto)
    knownCollections = Self.groupDefaults?.stringArray(forKey: AppGroup.knownCollectionsKey) ?? []
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(input.isFile ? "File" : "Link") {
          HStack(spacing: 10) {
            Image(systemName: mediaType.systemImage)
              .foregroundStyle(.tint)
            switch input {
            case .url(let url):
              Text(url.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            case .file(let name, let type, _):
              VStack(alignment: .leading, spacing: 1) {
                Text(name)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(2)
                Text(type.displayName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        if isOversized {
          Section {
          } footer: {
            Label("This file is too large to save (max 50 MB).", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }

        Section {
          HStack(spacing: 12) {
            modeOption(.auto, title: "Auto", subtitle: "Organized for you", systemImage: "wand.and.stars")
            modeOption(.manual, title: "Manual", subtitle: "You pick", systemImage: "slider.horizontal.3")
          }
          .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
          .listRowBackground(Color.clear)
        } footer: {
          if mode == .auto {
            Text(input.isFile
                 ? "SuStash will file this into a collection based on its type."
                 : "SuStash will file this link into a collection based on what it is.")
          }
        }

        if mode == .manual {
          Section("Collection") {
            TextField("e.g. Research, Recipes", text: $collection)
              .textInputAutocapitalization(.words)

            if !knownCollections.isEmpty {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                  ForEach(knownCollections, id: \.self) { name in
                    Button {
                      collection = name
                    } label: {
                      Text(name)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                          collection == name
                            ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                            : AnyShapeStyle(.quaternary),
                          in: Capsule()
                        )
                        .overlay(
                          Capsule().strokeBorder(
                            collection == name ? Color.accentColor : Color.clear,
                            lineWidth: 1
                          )
                        )
                    }
                    .buttonStyle(.plain)
                  }
                }
                .padding(.vertical, 2)
              }
            }
          }

          Section("Tags (comma-separated)") {
            TextField("e.g. ios, design, apple", text: $tags)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }

          // A file's type is inherited from the file — no picker.
          if !input.isFile {
            Section("Type") {
              Picker("Type", selection: $mediaType) {
                ForEach(MediaType.allCases, id: \.self) { type in
                  Label(type.displayName, systemImage: type.systemImage).tag(type)
                }
              }
              .pickerStyle(.menu)
            }
          }

          Section("Notes") {
            TextField("Optional", text: $notes, axis: .vertical)
              .lineLimit(3...6)
          }
        }
      }
      .animation(.snappy, value: mode)
      .navigationTitle("Save to SuStash")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: submit)
            .fontWeight(.semibold)
            .disabled(isOversized)
        }
      }
    }
  }

  private func modeOption(_ option: ShareSaveMode, title: String, subtitle: String, systemImage: String) -> some View {
    Button {
      mode = option
      Self.groupDefaults?.set(option.rawValue, forKey: AppGroup.preferredShareSaveModeKey)
    } label: {
      VStack(spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(mode == option ? Color.accentColor : Color.secondary)
          Image(systemName: systemImage)
          Text(title)
            .fontWeight(.semibold)
        }
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(uiColor: .secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(mode == option ? Color.accentColor : Color.clear, lineWidth: 1.5)
      )
    }
    .buttonStyle(.plain)
  }

  private func submit() {
    guard !didSubmit, !isOversized else { return }
    didSubmit = true

    let isAuto = mode == .auto
    var urlString = ""
    if case .url(let url) = input {
      urlString = url.absoluteString
    }

    let metadata = SharedLinkMetadata(
      url: urlString,
      collection: isAuto ? "" : collection.trimmingCharacters(in: .whitespacesAndNewlines),
      tags: isAuto ? [] : tags.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty },
      mediaType: mediaType.rawValue,
      notes: isAuto || notes.isEmpty ? nil : notes,
      autoOrganize: isAuto
    )
    onSave(metadata)
  }
}
