//
//  ColorTheme.swift
//  MindNative
//
//  Created by Claude Code
//

import SwiftUI

/// The "Ink and Depth" design system.
///
/// The canvas is treated as a lit surface viewed from above. Hierarchy is carried
/// by elevation rather than by decoration: a root idea sits closest to the viewer
/// with a saturated fill and a real shadow, and each level below it recedes with a
/// lighter tint, a thinner stroke, and less lift. Chrome stays quiet so the map is
/// the only thing competing for attention.
struct ColorTheme {
    // MARK: - Surfaces
    //
    // Hand-mixed indigo-slate rather than raw system grays. The canvas reads as a
    // deliberate material with a cool cast that makes warm node hues advance.
    static let bgPage = Color.adaptive(light: "#F7F8FB", dark: "#12141C")
    static let bgPageOuterFrame = Color.adaptive(light: "#EFF1F6", dark: "#0D0F16")
    static let bgCard = Color.adaptive(light: "#FFFFFF", dark: "#1E2230")
    static let bgCardSoft = Color.adaptive(light: "#F2F4F9", dark: "#171A24")

    /// Translucent chrome for the floating canvas controls.
    static let glassFill = Color.adaptive(light: "#FFFFFF", dark: "#1E2230")
    static let glassStroke = Color.adaptive(
        light: "#0B1020", lightAlpha: 0.09,
        dark: "#FFFFFF", darkAlpha: 0.12
    )

    // MARK: - Accent
    //
    // A teal-to-violet ramp. Teal anchors the interactive state, violet carries the
    // AI affordances, so "the machine is thinking" is legible by hue alone.
    static let accentPrimary = Color.adaptive(light: "#0F7B8A", dark: "#3BC4D4")

    /// Violet, reserved for on-device generation so AI surfaces are legible by
    /// hue alone rather than needing a label.
    static let accentAI = Color.adaptive(light: "#5B4BC4", dark: "#9C8CF0")

    // MARK: - Text
    static let textPrimary = Color.adaptive(light: "#141824", dark: "#F2F4FA")
    static let textSecondary = Color.adaptive(light: "#4A5266", dark: "#A2AAC0")
    static let textMuted = Color.adaptive(light: "#7A8296", dark: "#6E7689")

    // MARK: - Lines and depth
    static let borderSubtle = Color.adaptive(
        light: "#0B1020", lightAlpha: 0.10,
        dark: "#FFFFFF", darkAlpha: 0.10
    )
    static let borderStrong = Color.adaptive(
        light: "#0B1020", lightAlpha: 0.20,
        dark: "#FFFFFF", darkAlpha: 0.20
    )
    static let connectionLine = Color.adaptive(light: "#8A93A8", dark: "#5A6379")

    /// Ambient occlusion under a resting card.
    static let shadow = Color.adaptive(
        light: "#0B1020", lightAlpha: 0.14,
        dark: "#000000", darkAlpha: 0.55
    )
    /// The deeper cast a card throws while it is lifted mid-drag.
    static let shadowLifted = Color.adaptive(
        light: "#0B1020", lightAlpha: 0.22,
        dark: "#000000", darkAlpha: 0.75
    )
    // MARK: - Overlay
    static let overlayDim = Color.adaptive(
        light: "#0B1020", lightAlpha: 0.22,
        dark: "#05070C", darkAlpha: 0.62
    )

    // MARK: - Status
    static let statusSuccess = Color.adaptive(light: "#17795F", dark: "#3FD1A6")
    static let statusWarning = Color.adaptive(light: "#A5620C", dark: "#E9A83C")
    static let statusError = Color.adaptive(light: "#B8353B", dark: "#F2686E")

    // MARK: - Node palette
    //
    // Seven hues spaced around the wheel at a matched perceptual weight, so no
    // branch shouts louder than its neighbours. Every entry is legible as a tinted
    // fill behind body text in both appearances.
    static let nodePalette: [Color] = [
        Color.adaptive(light: "#0F7B8A", dark: "#3BC4D4"), // teal
        Color.adaptive(light: "#5B4BC4", dark: "#9C8CF0"), // violet
        Color.adaptive(light: "#B44A76", dark: "#F07AA6"), // rose
        Color.adaptive(light: "#A5620C", dark: "#E9A83C"), // amber
        Color.adaptive(light: "#17795F", dark: "#3FD1A6"), // green
        Color.adaptive(light: "#2C6BC4", dark: "#6BA8F5"), // blue
        Color.adaptive(light: "#8A5A3C", dark: "#D19A6E")  // clay
    ]
}

// MARK: - Appearance-aware color

extension Color {
    /// Builds a color that resolves per appearance, so a single token works in
    /// both light and dark without branching at every call site.
    static func adaptive(
        light: String,
        lightAlpha: Double = 1,
        dark: String,
        darkAlpha: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return NSColor(srgbHex: hex).withAlphaComponent(alpha)
        })
    }
}

private extension NSColor {
    /// Parses `#RRGGBB` into an sRGB color. Unparseable input falls back to a
    /// mid gray so a typo shows up as an obviously wrong swatch rather than
    /// silently rendering black.
    convenience init(srgbHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self.init(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
