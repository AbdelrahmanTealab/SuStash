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
  /// Types we accept as file saves, most specific first (GIF conforms to
  /// image, so it must be checked earlier).
  private static let fileTypes: [UTType] = [.pdf, .gif, .movie, .image, .audio]

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
          guard let self = self, let url = Self.extractURL(from: data), url.scheme != "file" else {
            self?.tryLoadFile(from: attachments)
            return
          }
          self.showComposer(for: .url(url), fileToken: nil, fileName: nil)
        }
        return
      }
    }
    // 2. Files (Photos, Files app, PDFs, videos…)
    tryLoadFile(from: attachments)
  }

  private func tryLoadFile(from attachments: [NSItemProvider]) {
    for type in Self.fileTypes {
      for provider in attachments where provider.hasItemConformingToTypeIdentifier(type.identifier) {
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] fileURL, _ in
          guard let self = self, let fileURL else {
            self?.tryLoadPlainText(from: attachments)
            return
          }
          self.stageFile(at: fileURL)
        }
        return
      }
    }
    // 3. Fallback: plain text containing a URL (YouTube and many apps).
    tryLoadPlainText(from: attachments)
  }

  /// Streams the provided file into the app-group inbox — the extension
  /// never holds the bytes in memory (its memory ceiling is tiny).
  private func stageFile(at sourceURL: URL) {
    let displayName = sourceURL.lastPathComponent
    let mediaType = MediaType.inferred(fromTypeIdentifier: UTType(filenameExtension: sourceURL.pathExtension)?.identifier ?? UTType.data.identifier)

    let size = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size <= AppGroup.maxSavedFileBytes else {
      showComposer(for: .file(displayName: displayName, mediaType: mediaType, oversized: true), fileToken: nil, fileName: displayName)
      return
    }

    guard let inbox = AppGroup.fileInboxURL else {
      closeExtension()
      return
    }
    let token = UUID().uuidString + "." + (sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension)
    do {
      try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: sourceURL, to: inbox.appendingPathComponent(token))
    } catch {
      closeExtension()
      return
    }

    showComposer(for: .file(displayName: displayName, mediaType: mediaType, oversized: false), fileToken: token, fileName: displayName)
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
          self.showComposer(for: .url(url), fileToken: nil, fileName: nil)
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

  private func showComposer(for input: ComposerInput, fileToken: String?, fileName: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let rootView = SaveComposerView(
        input: input,
        onSave: { [weak self] metadata in
          var payload = metadata
          payload.fileToken = fileToken
          payload.originalFileName = fileName
          self?.saveToSharedDefaults(payload)
          self?.closeExtension()
        },
        onCancel: { [weak self] in
          // Don't leave orphaned bytes in the inbox on cancel.
          if let fileToken, let inbox = AppGroup.fileInboxURL {
            try? FileManager.default.removeItem(at: inbox.appendingPathComponent(fileToken))
          }
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
