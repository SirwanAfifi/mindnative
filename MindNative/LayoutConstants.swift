import Foundation
import CoreGraphics

enum LayoutConstants {
    // MARK: - Node Positioning
    //
    // Nodes are positioned by their centre, so the horizontal gap has to clear
    // half of the parent's width plus half of the child's. A wide card plus the
    // old 200pt offset put children on top of their parent.
    static let horizontalOffset: CGFloat = 300
    // Centre-to-centre. A wrapped two-line card is ~58pt tall, so this keeps a
    // comfortable gap even when siblings are not single-line.
    static let verticalSpacing: CGFloat = 92
    static let circularRadius: CGFloat = 280

    // MARK: - Node Sizing
    static let nodeMinSize: CGFloat = 60
    static let nodeMinPadding: CGFloat = 60

    // MARK: - Layout Spacing
    static let minNodeDistance: CGFloat = 120
    static let siblingSeparation: CGFloat = 30

    // MARK: - Auto-layout Iterations
    static let maxSeparationIterations = 50
}
