import SwiftUI

struct MapNavigatorView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var query = ""

    private var roots: [IdeaNode] {
        viewModel.nodes.filter { $0.parentID == nil }
    }

    private var matches: [IdeaNode] {
        viewModel.searchResults(for: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Navigator", systemImage: "list.bullet.indent")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.isNavigatorPresented = false
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.plain)
                .help("Hide navigator")
                .accessibilityLabel("Hide navigator")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(roots) { node in
                            NavigatorBranchRow(
                                node: node,
                                viewModel: viewModel,
                                depth: 0
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No Ideas Found")
                        .font(.headline)
                    Text("Try a different title, note, tag, or link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(matches) { node in
                    NavigatorResultRow(node: node, viewModel: viewModel)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
        .background(.regularMaterial)
        .searchable(text: $query, placement: .sidebar, prompt: "Search ideas")
        .accessibilityIdentifier("map-navigator")
    }
}

private struct NavigatorBranchRow: View {
    let node: IdeaNode
    @ObservedObject var viewModel: CanvasViewModel
    let depth: Int

    private var children: [IdeaNode] {
        viewModel.children(of: node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            NavigatorNodeButton(
                node: node,
                viewModel: viewModel,
                depth: depth,
                hasChildren: !children.isEmpty
            )

            if !node.isCollapsed {
                ForEach(children) { child in
                    NavigatorBranchRow(
                        node: child,
                        viewModel: viewModel,
                        depth: depth + 1
                    )
                }
            }
        }
    }
}

private struct NavigatorNodeButton: View {
    let node: IdeaNode
    @ObservedObject var viewModel: CanvasViewModel
    let depth: Int
    let hasChildren: Bool

    private var isSelected: Bool {
        viewModel.selectedNodeIDs.contains(node.id)
    }

    var body: some View {
        HStack(spacing: 7) {
            if hasChildren {
                Button {
                    viewModel.toggleCollapsed(nodeID: node.id)
                } label: {
                    Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 14, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(node.isCollapsed ? "Expand branch" : "Collapse branch")
            } else {
                Color.clear.frame(width: 14, height: 18)
            }

            if let iconName = node.iconName {
                Image(systemName: iconName)
                    .foregroundStyle(node.color)
                    .frame(width: 15)
            } else {
                Circle()
                    .fill(node.color)
                    .frame(width: 7, height: 7)
                    .frame(width: 15)
            }

            Text(node.title.isEmpty ? "Untitled idea" : node.title)
                .lineLimit(1)
                .strikethrough(node.isTask && node.isCompleted)

            Spacer(minLength: 4)

            if node.isTask {
                Image(systemName: node.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(node.isCompleted ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, CGFloat(depth) * 16 + 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .padding(.horizontal, 6)
        .onTapGesture {
            viewModel.focusedNodeID = node.id
            viewModel.toggleNodeSelection(node.id, addToSelection: false)
        }
        .contextMenu {
            Button("Focus on Branch") {
                viewModel.focusOnBranch(node.id)
            }
            if node.parentID != nil {
                Button("Promote to Main Idea") {
                    viewModel.promoteToRoot(node.id)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(node.title.isEmpty ? "Untitled idea" : node.title)
        .accessibilityHint("Selects this idea on the canvas")
    }
}

private struct NavigatorResultRow: View {
    let node: IdeaNode
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        Button {
            viewModel.focusedNodeID = node.id
            viewModel.toggleNodeSelection(node.id, addToSelection: false)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(node.color)
                        .frame(width: 7, height: 7)
                    Text(node.title.isEmpty ? "Untitled idea" : node.title)
                        .fontWeight(.medium)
                }

                if !node.notes.isEmpty {
                    Text(node.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if !node.tags.isEmpty {
                    Text(node.tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
