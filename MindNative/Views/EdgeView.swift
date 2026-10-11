import SwiftUI

/// A connection drawn as a tapering branch rather than a wire.
///
/// The curve leaves its parent horizontally and arrives at its child the same
/// way, so a tree of them reads as one continuous growth. Line weight falls off
/// with depth and the stroke fades toward the child, which keeps dense maps from
/// turning into a thicket of equal-weight lines.
struct EdgeView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var elevation: NodeElevation = .branch
    var kind: ConnectionKind = .hierarchy
    var isHighlighted: Bool = false

    var body: some View {
        ZStack {
            // A soft underlay reads as the edge's own shadow on the canvas and
            // keeps the line legible where it crosses a card or the grid.
            path
                .stroke(
                    color.opacity(isHighlighted ? 0.18 : 0.10),
                    style: StrokeStyle(lineWidth: lineWidth + 3, lineCap: .round)
                )
                .blur(radius: 3)

            path
                .stroke(
                    gradient,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        dash: kind == .association ? [8, 6] : []
                    )
                )
        }
        .animation(Motion.hover, value: isHighlighted)
        .allowsHitTesting(false)
    }

    private var path: Path {
        Path { path in
            // Control points sit at a fraction of the horizontal run, so the
            // curve keeps its shape whether the child is close or far.
            let horizontalRun = to.x - from.x
            let slack = max(abs(horizontalRun) * 0.5, 28)
            let direction: CGFloat = horizontalRun < 0 ? -1 : 1

            path.move(to: from)
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + slack * direction, y: from.y),
                control2: CGPoint(x: to.x - slack * direction, y: to.y)
            )
        }
    }

    /// Fades from the parent's hue toward the child, giving each edge a
    /// direction you can read without an arrowhead.
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(isHighlighted ? 0.95 : 0.62),
                color.opacity(isHighlighted ? 0.55 : 0.30)
            ],
            startPoint: .init(x: 0, y: 0.5),
            endPoint: .init(x: 1, y: 0.5)
        )
    }

    private var lineWidth: CGFloat {
        let base = kind == .association ? max(1.4, elevation.edgeWidth * 0.85) : elevation.edgeWidth
        return isHighlighted ? base * 1.4 : base
    }
}
