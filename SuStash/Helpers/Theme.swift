//
//  Theme.swift
//  SuStash
//
//  Full theme system (Pro): each theme is a palette + typography + ambient
//  background pattern. All colors are dynamic (light/dark) so the separate
//  appearance setting (System/Light/Dark) keeps working per theme.
//  AppTheme's accessor API is stable — views never reference themes directly.
//

import SwiftUI
import UIKit

// MARK: - Theme catalog

enum ThemeChoice: String, CaseIterable, Identifiable {
    case classic
    case cottonCandy
    case cyberpunk
    case retro
    case neon
    case ocean
    case forest
    case mono
    case ozmantus
    case motta

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .cottonCandy: "Cotton Candy"
        case .cyberpunk: "Cyberpunk"
        case .retro: "Retro"
        case .neon: "Neon"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .mono: "Mono"
        case .ozmantus: "Ozmantus"
        case .motta: "Motta"
        }
    }

    var isProOnly: Bool { self != .classic }
}

enum ThemeFontStyle {
    case avenir
    case helvetica
    case rounded
    case serif
    case mono
    case typewriter
    case futura
    case gillSans
    case copperplate
    case script

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .avenir:
            return .custom(weight == .regular ? "AvenirNext-Medium" : "AvenirNext-\(weight == .bold ? "Bold" : "DemiBold")", size: size)
        case .helvetica:
            return .custom(weight == .regular ? "HelveticaNeue" : "HelveticaNeue-\(weight == .bold ? "Bold" : "Medium")", size: size)
        case .typewriter:
            return .custom(weight == .regular ? "AmericanTypewriter" : "AmericanTypewriter-Bold", size: size)
        case .futura:
            return .custom(weight == .regular ? "Futura-Medium" : "Futura-Bold", size: size)
        case .gillSans:
            return .custom(weight == .regular ? "GillSans" : "GillSans-SemiBold", size: size)
        case .copperplate:
            // Engraved display face — closest iOS-built-in to Herculanum,
            // which only ships on macOS.
            return .custom(weight == .regular ? "Copperplate" : "Copperplate-Bold", size: size)
        case .script:
            // Closest iOS-built-in to Brush Script MT (macOS/Monotype only).
            // Swap the names here once a licensed/OFL brush face is bundled.
            return .custom(weight == .regular ? "SnellRoundhand" : "SnellRoundhand-Bold", size: size)
        }
    }

    /// UIKit name for navigation-bar appearance (best effort).
    func uiFontName(bold: Bool) -> String? {
        switch self {
        case .avenir: bold ? "AvenirNext-Bold" : "AvenirNext-DemiBold"
        case .helvetica: bold ? "HelveticaNeue-Bold" : "HelveticaNeue-Medium"
        case .typewriter: "AmericanTypewriter-Bold"
        case .futura: bold ? "Futura-Bold" : "Futura-Medium"
        case .gillSans: bold ? "GillSans-Bold" : "GillSans-SemiBold"
        case .copperplate: bold ? "Copperplate-Bold" : "Copperplate"
        case .script: bold ? "SnellRoundhand-Bold" : "SnellRoundhand"
        case .rounded, .serif, .mono: nil // system designs handled separately
        }
    }
}

enum ThemeLinePattern {
    case curves
    case waves
    case grid
    case scanlines
    case beams
}

struct ThemeSpec {
    let accent: Color
    let background: Color
    let card: Color
    let headingStyle: ThemeFontStyle
    let bodyStyle: ThemeFontStyle
    let linePattern: ThemeLinePattern

    fileprivate init(
        accentLight: (CGFloat, CGFloat, CGFloat), accentDark: (CGFloat, CGFloat, CGFloat),
        backgroundLight: (CGFloat, CGFloat, CGFloat), backgroundDark: (CGFloat, CGFloat, CGFloat),
        cardLight: (CGFloat, CGFloat, CGFloat), cardDark: (CGFloat, CGFloat, CGFloat),
        headingStyle: ThemeFontStyle, bodyStyle: ThemeFontStyle, linePattern: ThemeLinePattern
    ) {
        accent = Self.dynamic(accentLight, accentDark)
        background = Self.dynamic(backgroundLight, backgroundDark)
        card = Self.dynamic(cardLight, cardDark)
        self.headingStyle = headingStyle
        self.bodyStyle = bodyStyle
        self.linePattern = linePattern
    }

    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    static func spec(for choice: ThemeChoice) -> ThemeSpec {
        switch choice {
        case .classic:
            ThemeSpec(
                accentLight: (0.39, 0.44, 0.90), accentDark: (0.62, 0.66, 1.00),
                backgroundLight: (0.965, 0.963, 0.975), backgroundDark: (0.055, 0.058, 0.078),
                cardLight: (1, 1, 1), cardDark: (0.105, 0.11, 0.14),
                headingStyle: .avenir, bodyStyle: .helvetica, linePattern: .curves
            )
        case .cottonCandy:
            ThemeSpec(
                accentLight: (0.93, 0.45, 0.70), accentDark: (1.00, 0.65, 0.83),
                backgroundLight: (0.99, 0.945, 0.965), backgroundDark: (0.13, 0.07, 0.13),
                cardLight: (1, 1, 1), cardDark: (0.19, 0.11, 0.19),
                headingStyle: .rounded, bodyStyle: .rounded, linePattern: .waves
            )
        case .cyberpunk:
            ThemeSpec(
                accentLight: (0.62, 0.15, 0.78), accentDark: (0.22, 1.00, 0.60),
                backgroundLight: (0.94, 0.94, 0.96), backgroundDark: (0.02, 0.03, 0.06),
                cardLight: (1, 1, 1), cardDark: (0.05, 0.08, 0.13),
                headingStyle: .mono, bodyStyle: .mono, linePattern: .grid
            )
        case .retro:
            ThemeSpec(
                accentLight: (0.77, 0.38, 0.18), accentDark: (0.92, 0.60, 0.36),
                backgroundLight: (0.965, 0.93, 0.865), backgroundDark: (0.13, 0.10, 0.06),
                cardLight: (1.00, 0.99, 0.965), cardDark: (0.19, 0.15, 0.10),
                headingStyle: .typewriter, bodyStyle: .typewriter, linePattern: .scanlines
            )
        case .neon:
            ThemeSpec(
                accentLight: (0.04, 0.66, 0.76), accentDark: (0.13, 0.95, 1.00),
                backgroundLight: (0.94, 0.95, 0.965), backgroundDark: (0.01, 0.015, 0.045),
                cardLight: (1, 1, 1), cardDark: (0.045, 0.06, 0.10),
                headingStyle: .futura, bodyStyle: .futura, linePattern: .beams
            )
        case .ocean:
            ThemeSpec(
                accentLight: (0.07, 0.45, 0.72), accentDark: (0.34, 0.74, 0.94),
                backgroundLight: (0.93, 0.955, 0.975), backgroundDark: (0.03, 0.09, 0.13),
                cardLight: (1, 1, 1), cardDark: (0.06, 0.14, 0.20),
                headingStyle: .gillSans, bodyStyle: .helvetica, linePattern: .waves
            )
        case .forest:
            ThemeSpec(
                accentLight: (0.18, 0.49, 0.28), accentDark: (0.44, 0.81, 0.56),
                backgroundLight: (0.94, 0.96, 0.93), backgroundDark: (0.06, 0.10, 0.07),
                cardLight: (1, 1, 1), cardDark: (0.10, 0.16, 0.11),
                headingStyle: .serif, bodyStyle: .serif, linePattern: .curves
            )
        case .mono:
            ThemeSpec(
                accentLight: (0.15, 0.15, 0.17), accentDark: (0.92, 0.92, 0.94),
                backgroundLight: (0.97, 0.97, 0.97), backgroundDark: (0.04, 0.04, 0.04),
                cardLight: (1, 1, 1), cardDark: (0.09, 0.09, 0.09),
                headingStyle: .helvetica, bodyStyle: .helvetica, linePattern: .beams
            )
        case .ozmantus:
            ThemeSpec(
                accentLight: (0.88, 0.44, 0.06), accentDark: (1.00, 0.60, 0.20),
                backgroundLight: (0.985, 0.955, 0.915), backgroundDark: (0.10, 0.055, 0.015),
                cardLight: (1.00, 0.99, 0.97), cardDark: (0.17, 0.10, 0.04),
                headingStyle: .copperplate, bodyStyle: .helvetica, linePattern: .curves
            )
        case .motta:
            // Emerald accent over sage-tinted surfaces.
            ThemeSpec(
                accentLight: (0.00, 0.58, 0.36), accentDark: (0.22, 0.83, 0.55),
                backgroundLight: (0.935, 0.955, 0.925), backgroundDark: (0.05, 0.085, 0.06),
                cardLight: (0.98, 1.00, 0.975), cardDark: (0.10, 0.15, 0.105),
                headingStyle: .script, bodyStyle: .helvetica, linePattern: .waves
            )
        }
    }
}

// MARK: - Live theme state

/// Source of truth for the active theme. @Observable means any view whose
/// body reads AppTheme colors/fonts re-renders the instant the choice
/// changes — no restart, and only theme-displaying views invalidate.
@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var choice: ThemeChoice {
        didSet {
            guard choice != oldValue else { return }
            UserDefaults(suiteName: AppGroup.identifier)?
                .set(choice.rawValue, forKey: "appTheme")
            Self.applyNavigationBarFonts(for: choice)
        }
    }

    private init() {
        let stored = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: "appTheme")
        choice = stored.flatMap(ThemeChoice.init(rawValue:)) ?? .classic
    }

    /// UIKit appearance proxies only affect newly created bars — call on
    /// launch and on switch; long-lived bars are refreshed via .id rebuilds.
    static func applyNavigationBarFonts(for choice: ThemeChoice) {
        let style = ThemeSpec.spec(for: choice).headingStyle
        let navBar = UINavigationBar.appearance()
        if let largeName = style.uiFontName(bold: true), let largeFont = UIFont(name: largeName, size: 34) {
            navBar.largeTitleTextAttributes = [.font: largeFont]
        } else {
            navBar.largeTitleTextAttributes = nil
        }
        if let titleName = style.uiFontName(bold: false), let titleFont = UIFont(name: titleName, size: 17) {
            navBar.titleTextAttributes = [.font: titleFont]
        } else {
            navBar.titleTextAttributes = nil
        }
    }
}

// MARK: - Stable accessor API

@MainActor
enum AppTheme {
    static var currentChoice: ThemeChoice {
        ThemeManager.shared.choice
    }

    static var spec: ThemeSpec { ThemeSpec.spec(for: currentChoice) }

    static var accent: Color { spec.accent }
    static var background: Color { spec.background }
    static var card: Color { spec.card }

    static func accentColor(for choice: ThemeChoice) -> Color {
        ThemeSpec.spec(for: choice).accent
    }

    static func titleFont(_ size: CGFloat) -> Font {
        spec.headingStyle.font(size: size, weight: .bold)
    }

    static func headingFont(_ size: CGFloat) -> Font {
        spec.headingStyle.font(size: size, weight: .semibold)
    }

    static func bodyFont(_ size: CGFloat) -> Font {
        spec.bodyStyle.font(size: size, weight: .medium)
    }

    static func captionFont(_ size: CGFloat) -> Font {
        spec.bodyStyle.font(size: size, weight: .regular)
    }

    /// Media-type badge palette — theme-independent so type recognition
    /// stays consistent across themes.
    static func badgeColor(for mediaType: MediaType) -> Color {
        switch mediaType {
        case .article: soft(1.00, 0.62, 0.30)
        case .video: soft(0.94, 0.42, 0.44)
        case .image: soft(0.68, 0.51, 0.93)
        case .gif: soft(0.91, 0.47, 0.85)
        case .audio: soft(0.93, 0.45, 0.65)
        case .pdf: soft(0.28, 0.72, 0.71)
        case .document: soft(0.36, 0.62, 0.94)
        case .code: soft(0.48, 0.52, 0.94)
        case .product: soft(0.24, 0.69, 0.53)
        case .bookmark: soft(0.56, 0.58, 0.66)
        }
    }

    private static func soft(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> Color {
        Color(uiColor: UIColor(red: red, green: green, blue: blue, alpha: 1))
    }
}

// MARK: - Ambient background

/// Theme background color plus the theme's slow, faint line animation.
/// Drop-in replacement for `.background(AppTheme.background)`.
struct ThemedScreenBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.background
            if reduceMotion {
                AmbientLinesCanvas(pattern: AppTheme.spec.linePattern, accent: AppTheme.accent, time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                    AmbientLinesCanvas(
                        pattern: AppTheme.spec.linePattern,
                        accent: AppTheme.accent,
                        time: context.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Deliberately restrained: a handful of 1pt paths at ~5% opacity, phase
/// driven by a 45–75 second period so motion is barely perceptible.
private struct AmbientLinesCanvas: View {
    let pattern: ThemeLinePattern
    let accent: Color
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let color = accent.opacity(0.05)
            switch pattern {
            case .curves, .waves:
                let amplitude: CGFloat = pattern == .waves ? 22 : 40
                let phase = CGFloat(time.truncatingRemainder(dividingBy: 60) / 60) * .pi * 2
                for lane in 0..<3 {
                    var path = Path()
                    let baseY = size.height * (0.25 + 0.25 * CGFloat(lane))
                    let laneShift = CGFloat(lane) * 1.7
                    path.move(to: CGPoint(x: -10, y: baseY))
                    var x: CGFloat = -10
                    while x <= size.width + 10 {
                        let y = baseY + sin(x / 140 + phase + laneShift) * amplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 12
                    }
                    context.stroke(path, with: .color(color), lineWidth: 1)
                }
            case .grid:
                let spacing: CGFloat = 56
                let drift = CGFloat(time.truncatingRemainder(dividingBy: 75) / 75) * spacing
                var path = Path()
                var x = -spacing + drift
                while x <= size.width + spacing {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y = -spacing + drift
                while y <= size.height + spacing {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(color), lineWidth: 0.75)
            case .scanlines:
                let spacing: CGFloat = 34
                let drift = CGFloat(time.truncatingRemainder(dividingBy: 50) / 50) * spacing
                var path = Path()
                var y = -spacing + drift
                while y <= size.height + spacing {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            case .beams:
                let spacing: CGFloat = 90
                let drift = CGFloat(time.truncatingRemainder(dividingBy: 70) / 70) * spacing
                var path = Path()
                var offset = -size.height - spacing + drift
                while offset <= size.width + spacing {
                    path.move(to: CGPoint(x: offset, y: size.height + 10))
                    path.addLine(to: CGPoint(x: offset + size.height, y: -10))
                    offset += spacing
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
