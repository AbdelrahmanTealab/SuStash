//
//  ShareViewController.swift
//  SuStashShareExtension
//
//  Created by Abdelrahman  Tealab on 2025-05-16.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
          let attachments = item.attachments else {
      closeExtension()
      return
    }

    tryLoadURL(from: attachments)
  }

  private func tryLoadURL(from attachments: [NSItemProvider]) {
    // 1. Try public.url first (Safari, etc.)
    for provider in attachments {
      if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] data, _ in
          guard let self = self, let url = Self.extractURL(from: data) else {
            self?.tryLoadPlainText(from: attachments)
            return
          }
          self.showShareInput(for: url)
        }
        return
      }
    }
    // 2. Fallback: try plain text (YouTube, many other apps share URLs as text)
    tryLoadPlainText(from: attachments)
  }

  private func tryLoadPlainText(from attachments: [NSItemProvider]) {
    for provider in attachments {
      if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, _ in
          guard let self = self else { return }
          let text = data as? String ?? (data as? Data).flatMap { String(data: $0, encoding: .utf8) }
          guard let text = text, let url = Self.firstURL(in: text) else {
            self.closeExtension()
            return
          }
          self.showShareInput(for: url)
        }
        return
      }
    }
    closeExtension()
  }

  private static func extractURL(from value: Any?) -> URL? {
    guard let value = value else { return nil }
    if let u = value as? URL { return u }
    if let s = value as? String { return URL(string: s) }
    if let dict = value as? [String: Any] {
      let s = (dict["URL"] as? String) ?? (dict["url"] as? String)
        ?? (dict["URL"] as? URL)?.absoluteString ?? (dict["url"] as? URL)?.absoluteString
      if let s = s { return URL(string: s) }
    }
    return nil
  }

  /// Finds a URL inside free-form text. Uses a data detector rather than
  /// URL(string:) — almost any single word parses as a valid URL, which
  /// would let garbage text through.
  private static func firstURL(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    return match?.url
  }

  private func showShareInput(for url: URL) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let rootView = ShareInputView(
        sharedURL: url,
        onSave: { [weak self] metadata in
          self?.saveToSharedDefaults(metadata)
          self?.closeExtension()
        },
        onCancel: { [weak self] in
          self?.closeExtension()
        }
      )
      let hosting = UIHostingController(rootView: rootView)
      self.addChild(hosting)
      hosting.view.translatesAutoresizingMaskIntoConstraints = false
      self.view.addSubview(hosting.view)
      NSLayoutConstraint.activate([
        hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor),
        hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
        hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
      ])
      hosting.didMove(toParent: self)
    }
  }

  private func saveToSharedDefaults(_ metadata: SharedLinkMetadata) {
    let defaults = UserDefaults(suiteName: AppGroup.identifier)
    var stored = defaults?.data(forKey: AppGroup.sharedLinkQueueKey).flatMap {
      try? JSONDecoder().decode([SharedLinkMetadata].self, from: $0)
    } ?? []

    stored.append(metadata)

    if let encoded = try? JSONEncoder().encode(stored) {
      defaults?.set(encoded, forKey: AppGroup.sharedLinkQueueKey)
      // The extension process can be killed immediately after
      // completeRequest; make sure the queue write hits disk first.
      defaults?.synchronize()
    }
  }

  private func closeExtension() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
