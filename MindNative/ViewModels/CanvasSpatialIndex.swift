import CoreGraphics
import Foundation

struct CanvasSpatialIndex {
    private let cellSize: CGFloat
    private var buckets: [Cell: Set<UUID>] = [:]
    private var positions: [UUID: CGPoint] = [:]

    init(cellSize: CGFloat = 480) {
        self.cellSize = cellSize
    }

    mutating func rebuild(nodes: [IdeaNode]) {
        buckets.removeAll(keepingCapacity: true)
        positions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        for node in nodes {
            buckets[cell(for: node.position), default: []].insert(node.id)
        }
    }

    func identifiers(in rect: CGRect, padding: CGFloat = 260) -> Set<UUID> {
        guard !positions.isEmpty else { return [] }
        let expanded = rect.insetBy(dx: -padding, dy: -padding)
        let minCell = cell(for: CGPoint(x: expanded.minX, y: expanded.minY))
        let maxCell = cell(for: CGPoint(x: expanded.maxX, y: expanded.maxY))
        var result = Set<UUID>()

        for x in minCell.x...maxCell.x {
            for y in minCell.y...maxCell.y {
                result.formUnion(buckets[Cell(x: x, y: y)] ?? [])
            }
        }
        return result
    }

    private func cell(for point: CGPoint) -> Cell {
        Cell(
            x: Int(floor(point.x / cellSize)),
            y: Int(floor(point.y / cellSize))
        )
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }
}
