//
//  AppSettings.swift
//  SuStash
//
//  User preferences, stored in the app group so the share extension can
//  read the ones it cares about (default save mode).
//

import Foundation
import SwiftUI

enum TapBehavior: String, CaseIterable, Identifiable {
    case openLink
    case copyLink
    case shareLink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openLink: "Open Link"
        case .copyLink: "Copy URL"
        case .shareLink: "Share URL"
        }
    }

    var systemImage: String {
        switch self {
        case .openLink: "safari"
        case .copyLink: "doc.on.doc"
        case .shareLink: "square.and.arrow.up"
        }
    }
}

enum AppearanceOverride: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppSettings {
    static let store = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    static let tapBehaviorKey = "tapBehavior"
    static let appearanceKey = "appearanceOverride"
    static let themeKey = "appTheme"
    static let homeViewModeKey = "homeViewMode"

    static var tapBehavior: TapBehavior {
        store.string(forKey: tapBehaviorKey).flatMap(TapBehavior.init(rawValue:)) ?? .openLink
    }
}
