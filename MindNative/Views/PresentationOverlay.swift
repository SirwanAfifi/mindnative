import SwiftUI

struct PresentationOverlay: View {
    let node: IdeaNode
    let index: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack {
            HStack {
                Label("Presentation", systemImage: "play.rectangle")
                    .font(.headline)

                Spacer()

                Text("\(index + 1) of \(total)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button("Done", action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            Spacer()

            VStack(spacing: 12) {
                if let iconName = node.iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 30))
                        .foregroundStyle(node.color)
                }

                Text(node.title.isEmpty ? "Untitled idea" : node.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                if !node.notes.isEmpty {
                    Text(node.notes)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(8)
                }
            }
            .padding(30)
            .frame(maxWidth: 720)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(node.color.opacity(0.55), lineWidth: 2)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onPrevious) {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(index == 0)

                Button(action: onNext) {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(index + 1 >= total)
            }
            .controlSize(.large)
            .padding(12)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Presentation mode")
        .accessibilityIdentifier("presentation-overlay")
    }
}
