import SwiftUI

struct MinimapView: View {
    @ObservedObject var viewModel: CanvasViewModel

    private var bounds: CGRect {
        guard let first = viewModel.visibleNodes.first else { return .zero }
        return viewModel.visibleNodes.dropFirst().reduce(
            CGRect(
                x: first.position.x - 80,
                y: first.position.y - 38,
                width: 160,
                height: 76
            )
        ) { partial, node in
            partial.union(
                CGRect(
                    x: node.position.x - 80,
                    y: node.position.y - 38,
                    width: 160,
                    height: 76
                )
            )
        }
        .insetBy(dx: -60, dy: -60)
    }

    var body: some View {
        Canvas { context, size in
            guard !viewModel.visibleNodes.isEmpty,
                  bounds.width > 0,
                  bounds.height > 0 else { return }

            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let origin = CGPoint(
                x: (size.width - bounds.width * scale) / 2,
                y: (size.height - bounds.height * scale) / 2
            )

            func point(_ source: CGPoint) -> CGPoint {
                CGPoint(
                    x: origin.x + (source.x - bounds.minX) * scale,
                    y: origin.y + (source.y - bounds.minY) * scale
                )
            }

            for connection in viewModel.visibleConnections {
                guard let from = viewModel.getNode(by: connection.fromNodeID),
                      let to = viewModel.getNode(by: connection.toNodeID) else {
                    continue
                }
                var path = Path()
                path.move(to: point(from.position))
                path.addLine(to: point(to.position))
                context.stroke(
                    path,
                    with: .color(connection.color.opacity(0.55)),
                    style: StrokeStyle(
                        lineWidth: connection.kind == .association ? 1 : 1.5,
                        dash: connection.kind == .association ? [3, 2] : []
                    )
                )
            }

            for node in viewModel.visibleNodes {
                let center = point(node.position)
                let rect = CGRect(
                    x: center.x - max(3, 34 * scale),
                    y: center.y - max(2, 16 * scale),
                    width: max(6, 68 * scale),
                    height: max(4, 32 * scale)
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(
                        viewModel.selectedNodeIDs.contains(node.id)
                            ? node.color
                            : node.color.opacity(0.55)
                    )
                )
            }

            let viewportOrigin = CGPoint(
                x: (-viewModel.canvasOffset.width / viewModel.zoomScale),
                y: (-viewModel.canvasOffset.height / viewModel.zoomScale)
            )
            let viewportRect = CGRect(
                origin: point(viewportOrigin),
                size: CGSize(
                    width: viewModel.viewportSize.width / viewModel.zoomScale * scale,
                    height: viewModel.viewportSize.height / viewModel.zoomScale * scale
                )
            )
            context.stroke(
                Path(roundedRect: viewportRect, cornerRadius: 3),
                with: .color(Color.accentColor.opacity(0.9)),
                lineWidth: 1
            )
        }
        .frame(width: 170, height: 108)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map overview")
        .accessibilityValue("\(viewModel.visibleNodes.count) visible ideas")
    }
}
