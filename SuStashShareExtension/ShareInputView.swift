//
//  ShareInputView.swift
//  SuStashShareExtension
//
//  Created by Abdelrahman  Tealab on 2025-05-16.
//

import SwiftUI

enum ShareSaveMode: String {
  case auto
  case manual
}

struct ShareInputView: View {
  let sharedURL: URL
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

  init(sharedURL: URL, onSave: @escaping (SharedLinkMetadata) -> Void, onCancel: @escaping () -> Void) {
    self.sharedURL = sharedURL
    self.onSave = onSave
    self.onCancel = onCancel
    _mediaType = State(initialValue: .inferred(from: sharedURL))

    let saved = Self.groupDefaults?.string(forKey: AppGroup.preferredShareSaveModeKey)
    _mode = State(initialValue: saved.flatMap(ShareSaveMode.init(rawValue:)) ?? .auto)
    knownCollections = Self.groupDefaults?.stringArray(forKey: AppGroup.knownCollectionsKey) ?? []
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Link") {
          HStack(spacing: 10) {
            Image(systemName: mediaType.systemImage)
              .foregroundStyle(.tint)
            Text(sharedURL.absoluteString)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(3)
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
            Text("SuStash will file this link into a collection based on what it is.")
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
    guard !didSubmit else { return }
    didSubmit = true

    let isAuto = mode == .auto
    let metadata = SharedLinkMetadata(
      url: sharedURL.absoluteString,
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
