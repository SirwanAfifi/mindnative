//
//  DesignSystem.swift
//  MindNative
//
//  Created by Claude Code
//

import SwiftUI

/// How far an idea sits from the viewer.
///
/// Depth is the organising idea of the interface: a root concept is closest and
/// most saturated, and each generation below it recedes. Every card derives its
/// fill, stroke, shadow, and type scale from this one value so a branch reads as
/// a branch without the user tracing edges.
enum NodeElevation: Equatable {
    case root
    case branch
    case leaf

    /// Levels beyond the second all render as leaves; past that point the
    /// differences stop being readable and start looking like inconsistency.
    init(depth: Int) {
        switch depth {
        case 0: self = .root
        case 1: self = .branch
        default: self = .leaf
        }
    }

    // MARK: - Form

    var cornerRadius: CGFloat {
        switch self {
        case .root: return 16
        case .branch: return 13
        case .leaf: return 11
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .root: return 18
        case .branch: return 15
        case .leaf: return 13
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .root: return 15
        case .branch: return 12
        case .leaf: return 10
        }
    }

    /// Floor only — cards hug their text. These are sized so a one- or two-word
    /// label still reads as a card rather than an empty bar, without padding
    /// short titles like "Hi" into slabs.
    var minWidth: CGFloat {
        switch self {
        case .root: return 96
        case .branch: return 84
        case .leaf: return 76
        }
    }

    /// Ceiling before a long title wraps, scaled so a root can carry a fuller
    /// phrase than a leaf.
    var maxTextWidth: CGFloat {
        switch self {
        case .root: return 230
        case .branch: return 200
        case .leaf: return 180
        }
    }

    // MARK: - Type

    var fontSize: CGFloat {
        switch self {
        case .root: return 17
        case .branch: return 14
        case .leaf: return 13
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .root: return .bold
        case .branch: return .semibold
        case .leaf: return .medium
        }
    }

    // MARK: - Depth cues
    //
    // Tint, stroke, and shadow all fall off together. Reading them as one signal
    // is what makes the hierarchy legible at a glance rather than a lookup.

    /// Strength of the node's own hue washed into the card fill.
    var tintOpacity: Double {
        switch self {
        case .root: return 0.24
        case .branch: return 0.13
        case .leaf: return 0.07
        }
    }

    var strokeOpacity: Double {
        switch self {
        case .root: return 0.55
        case .branch: return 0.38
        case .leaf: return 0.26
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .root: return 1.5
        case .branch: return 1.25
        case .leaf: return 1
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .root: return 18
        case .branch: return 11
        case .leaf: return 7
        }
    }

    var shadowOffsetY: CGFloat {
        switch self {
        case .root: return 8
        case .branch: return 5
        case .leaf: return 3
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .root: return 1.0
        case .branch: return 0.75
        case .leaf: return 0.5
        }
    }

    /// Accent rail height beside the title. Roots get a fuller stroke.
    var railHeight: CGFloat {
        switch self {
        case .root: return 26
        case .branch: return 20
        case .leaf: return 17
        }
    }

    /// Edges thin out as they travel away from the trunk, the way a branch does.
    var edgeWidth: CGFloat {
        switch self {
        case .root: return 2.4
        case .branch: return 1.8
        case .leaf: return 1.3
        }
    }
}

/// Shared motion curves, so interactions across the app feel like one hand made them.
enum Motion {
    /// Settling a card into place after a drag or a layout pass.
    static let settle = Animation.spring(response: 0.34, dampingFraction: 0.74)
    /// Chrome and overlays appearing.
    static let chrome = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// Hover and focus, fast enough to feel attached to the pointer.
    static let hover = Animation.easeOut(duration: 0.14)
}
