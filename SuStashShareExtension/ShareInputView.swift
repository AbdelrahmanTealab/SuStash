//
//  ShareInputView.swift
//  SuStashShareExtension
//
//  Created by Abdelrahman  Tealab on 2025-05-16.
//

import SwiftUI

struct ShareInputView: View {
  var sharedURL: URL
  var onComplete: (SharedLinkMetadata) -> Void

  @State private var collection: String = ""
  @State private var tags: String = ""
  @State private var mediaType: String = "article"
  @State private var notes: String = ""

  let mediaTypes = ["article", "video", "image", "audio", "pdf", "document", "code", "tweet", "thread", "bookmark"]

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Link")) {
          Text(sharedURL.absoluteString)
            .font(.footnote)
            .lineLimit(3)
        }

        Section(header: Text("Collection")) {
          TextField("e.g. Research, Recipes", text: $collection)
        }

        Section(header: Text("Tags (comma-separated)")) {
          TextField("e.g. ios, design, apple", text: $tags)
        }

        Section(header: Text("Media Type")) {
          Picker("Media Type", selection: $mediaType) {
            ForEach(mediaTypes, id: \.self) { type in
              Text(type.capitalized).tag(type)
            }
          }
          .pickerStyle(MenuPickerStyle())
        }

        Section(header: Text("Notes")) {
          TextEditor(text: $notes)
            .frame(minHeight: 60)
        }
      }
      .navigationBarTitle("Save to SuStash", displayMode: .inline)
      .navigationBarItems(trailing: Button("Save") {
        let metadata = SharedLinkMetadata(
          url: sharedURL.absoluteString,
          collection: collection,
          tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
          mediaType: mediaType,
          notes: notes
        )
        onComplete(metadata)
      })
    }
  }
}
