//
//  ShareViewController.swift
//  SuStashShareExtension
//
//  Created by Abdelrahman  Tealab on 2025-05-16.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct SharedLinkMetadata: Codable {
  var url: String
  var collection: String
  var tags: [String]
  var mediaType: String
  var notes: String?
  var dateSaved: Date = Date()
}

class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
          let attachments = item.attachments else {
      closeExtension()
      return
    }

    for provider in attachments {
      if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, error in
          guard let url = data as? URL else {
            self.closeExtension()
            return
          }

          DispatchQueue.main.async {
            let rootView = ShareInputView(sharedURL: url) { metadata in
              self.saveToSharedDefaults(metadata)
              self.closeExtension()
            }

            let hosting = UIHostingController(rootView: rootView)
            self.addChild(hosting)
            hosting.view.frame = self.view.bounds
            self.view.addSubview(hosting.view)
            hosting.didMove(toParent: self)
          }
        }
        return
      }
    }

    closeExtension()
  }

  private func saveToSharedDefaults(_ metadata: SharedLinkMetadata) {
    let defaults = UserDefaults(suiteName: "group.com.atealab.sustash")
    var stored = defaults?.data(forKey: "sharedLinkItems").flatMap {
      try? JSONDecoder().decode([SharedLinkMetadata].self, from: $0)
    } ?? []

    stored.append(metadata)

    if let encoded = try? JSONEncoder().encode(stored) {
      defaults?.set(encoded, forKey: "sharedLinkItems")
    }
  }

  private func closeExtension() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
