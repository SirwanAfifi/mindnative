import Foundation

enum MindMapLayout: String, CaseIterable, Identifiable, Codable {
    case horizontal
    case vertical
    case radial
    case compact
    case cleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: "Horizontal Tree"
        case .vertical: "Vertical Tree"
        case .radial: "Radial"
        case .compact: "Compact"
        case .cleanup: "Clean Up Freeform"
        }
    }

    var systemImage: String {
        switch self {
        case .horizontal: "arrow.right"
        case .vertical: "arrow.down"
        case .radial: "circle.hexagongrid"
        case .compact: "rectangle.compress.vertical"
        case .cleanup: "wand.and.stars"
        }
    }
}

struct LayoutEngine {
    static func computeLayout(
        nodes: [IdeaNode],
        style: MindMapLayout
    ) -> [UUID: CGPoint] {
        switch style {
        case .horizontal:
            return computeTreeLayout(nodes: nodes)
        case .vertical:
            return computeVerticalLayout(nodes: nodes)
        case .radial:
            return computeRadialLayout(nodes: nodes)
        case .compact:
            return computeTreeLayout(
                nodes: nodes,
                horizontalOffset: 220,
                siblingSeparation: 28,
                nodeMinSize: 76
            )
        case .cleanup:
            return Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        }
    }

    /// Computes a hierarchical layout for the given nodes, preserving the x of root nodes and laying out subtrees to the right.
    /// - Parameters:
    ///   - nodes: The current list of nodes.
    ///   - horizontalOffset: The horizontal distance between parent and child levels.
    ///   - siblingSeparation: Extra vertical spacing between siblings.
    ///   - nodeMinSize: Base height to allocate for a leaf node's vertical footprint.
    /// - Returns: A mapping from node ID to new position.
    static func computeTreeLayout(
        nodes: [IdeaNode],
        horizontalOffset: CGFloat = LayoutConstants.horizontalOffset,
        siblingSeparation: CGFloat = LayoutConstants.siblingSeparation,
        nodeMinSize: CGFloat = LayoutConstants.nodeMinSize
    ) -> [UUID: CGPoint] {
        // Index children by parent for fast traversal.
        var childrenByParent: [UUID: [IdeaNode]] = [:]
        for node in nodes {
            if let pid = node.parentID {
                childrenByParent[pid, default: []].append(node)
            }
        }

        // Find roots (nodes with no parent)
        let roots = nodes.filter { $0.parentID == nil }
        var positions: [UUID: CGPoint] = [:]

        // Precompute subtree heights
        var subtreeHeights: [UUID: CGFloat] = [:]
        func computeHeight(_ id: UUID) -> CGFloat {
            if let cached = subtreeHeights[id] { return cached }
            let kids = childrenByParent[id] ?? []
            if kids.isEmpty {
                subtreeHeights[id] = nodeMinSize
                return nodeMinSize
            }
            var total: CGFloat = 0
            for (index, child) in kids.enumerated() {
                total += computeHeight(child.id)
                if index < kids.count - 1 { total += siblingSeparation }
            }
            let h = max(nodeMinSize, total)
            subtreeHeights[id] = h
            return h
        }

        // Layout a subtree given a starting x and y center
        func layoutSubtree(root: IdeaNode, startX: CGFloat, startY: CGFloat) {
            positions[root.id] = CGPoint(x: startX, y: startY)
            let kids = childrenByParent[root.id] ?? []
            guard !kids.isEmpty else { return }

            let totalHeight = computeHeight(root.id)
            var currentY = startY - totalHeight / 2
            for (index, child) in kids.enumerated() {
                let childHeight = computeHeight(child.id)
                let childCenterY = currentY + childHeight / 2
                positions[child.id] = CGPoint(x: startX + horizontalOffset, y: childCenterY)
                layoutSubtree(root: child, startX: startX + horizontalOffset, startY: childCenterY)

                currentY += childHeight
                if index < kids.count - 1 { currentY += siblingSeparation }
            }
        }

        for root in roots {
            // Preserve the root's original position as anchor
            layoutSubtree(root: root, startX: root.position.x, startY: root.position.y)
        }

        return positions
    }

    static func computeVerticalLayout(nodes: [IdeaNode]) -> [UUID: CGPoint] {
        let horizontal = computeTreeLayout(nodes: nodes)
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var rootByID: [UUID: UUID] = [:]

        for node in nodes {
            var current = node
            var visited = Set<UUID>()
            while let parentID = current.parentID,
                  visited.insert(current.id).inserted,
                  let parent = nodeByID[parentID] {
                current = parent
            }
            rootByID[node.id] = current.id
        }

        return Dictionary(uniqueKeysWithValues: nodes.map { node in
            let root = rootByID[node.id].flatMap { nodeByID[$0] } ?? node
            let point = horizontal[node.id] ?? node.position
            return (
                node.id,
                CGPoint(
                    x: root.position.x + point.y - root.position.y,
                    y: root.position.y + point.x - root.position.x
                )
            )
        })
    }

    static func computeRadialLayout(
        nodes: [IdeaNode],
        levelSpacing: CGFloat = 210
    ) -> [UUID: CGPoint] {
        let children = Dictionary(grouping: nodes.compactMap { node in
            node.parentID.map { ($0, node) }
        }, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        let roots = nodes.filter { $0.parentID == nil }
        var positions: [UUID: CGPoint] = [:]

        for root in roots {
            positions[root.id] = root.position
            var ordered: [(node: IdeaNode, depth: Int)] = []

            func appendDescendants(of node: IdeaNode, depth: Int) {
                for child in children[node.id] ?? [] {
                    ordered.append((child, depth))
                    appendDescendants(of: child, depth: depth + 1)
                }
            }
            appendDescendants(of: root, depth: 1)

            guard !ordered.isEmpty else { continue }
            let countByDepth = Dictionary(grouping: ordered, by: \.depth)
            for (depth, items) in countByDepth {
                for (index, item) in items.enumerated() {
                    let angle = (Double(index) / Double(items.count)) * 2 * Double.pi
                        - Double.pi / 2
                    let radius = CGFloat(depth) * levelSpacing
                    positions[item.node.id] = CGPoint(
                        x: root.position.x + cos(angle) * radius,
                        y: root.position.y + sin(angle) * radius
                    )
                }
            }
        }

        return positions
    }

    /// Applies a simple force-like separation to reduce overlaps between nodes.
    /// - Parameters:
    ///   - nodes: Current nodes (positions may be updated by layout first).
    ///   - minDistance: Minimum desired distance between unrelated nodes.
    ///   - relationAttenuation: Factor to reduce threshold for direct parent-child pairs.
    ///   - maxIterations: Maximum iterations to attempt separation.
    /// - Returns: A mapping with adjusted positions for nodes that moved.
    static func separateOverlaps(
        nodes: [IdeaNode],
        minDistance: CGFloat = LayoutConstants.minNodeDistance,
        relationAttenuation: CGFloat = 0.8,
        maxIterations: Int = LayoutConstants.maxSeparationIterations
    ) -> [UUID: CGPoint] {
        var positions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })

        func isDirectRelation(_ a: IdeaNode, _ b: IdeaNode) -> Bool {
            return a.parentID == b.id || b.parentID == a.id
        }

        guard nodes.count > 1 else { return positions }

        for _ in 0..<maxIterations {
            var changed = false
            for i in 0..<(nodes.count - 1) {
                let n1 = nodes[i]
                for j in (i + 1)..<nodes.count {
                    let n2 = nodes[j]
                    let p1 = positions[n1.id] ?? n1.position
                    let p2 = positions[n2.id] ?? n2.position
                    let dx = p2.x - p1.x
                    let dy = p2.y - p1.y
                    let dist = sqrt(dx * dx + dy * dy)
                    let threshold = isDirectRelation(n1, n2) ? minDistance * relationAttenuation : minDistance
                    if dist < threshold {
                        // Give perfectly overlapping nodes a stable direction so they can separate.
                        let angle = dist == 0
                            ? CGFloat((i + j).isMultiple(of: 2) ? 0 : Double.pi / 2)
                            : atan2(dy, dx)
                        let separation = (threshold - dist) / 2
                        let offsetX = cos(angle) * separation
                        let offsetY = sin(angle) * separation
                        positions[n1.id] = CGPoint(x: p1.x - offsetX, y: p1.y - offsetY)
                        positions[n2.id] = CGPoint(x: p2.x + offsetX, y: p2.y + offsetY)
                        changed = true
                    }
                }
            }
            if !changed { break }
        }

        return positions
    }
}
