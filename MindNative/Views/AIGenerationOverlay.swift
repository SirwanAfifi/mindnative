import SwiftUI

struct AIGenerationOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false
    @State private var generationTask: Task<Void, Never>?
    @State private var pulse: Bool = false
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var parentNode: IdeaNode? {
        guard let parentID = viewModel.generationParentNodeID else { return nil }
        return viewModel.getNode(by: parentID)
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                header
                promptField
                privacyNote
            }
            .padding(20)
            .frame(maxWidth: 600)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        // A violet edge-light along the top marks the panel as
                        // the AI surface without tinting the whole sheet.
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ColorTheme.accentAI.opacity(0.55),
                                        ColorTheme.glassStroke
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: ColorTheme.shadow, radius: 30, y: 14)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ColorTheme.overlayDim
                .contentShape(Rectangle())
                .onTapGesture { if !isProcessing { cancel() } }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .onAppear {
            inputText = viewModel.generationPrompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                inputFocused = true
            }
        }
        .onChange(of: isProcessing) { processing in
            // Skip the repeating pulse when the system asks for less motion.
            pulse = processing && !reduceMotion
        }
        .onExitCommand {
            cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            statusBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(parentNode == nil ? "Start a brainstorm" : "Expand this idea")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(ColorTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(ColorTheme.bgCardSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColorTheme.textSecondary)
            .help(isProcessing ? "Cancel generation" : "Close")
        }
    }

    /// While the model works, the badge breathes. It is the only motion on
    /// screen, so "still thinking" needs no copy.
    private var statusBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ColorTheme.accentAI.opacity(0.14))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ColorTheme.accentAI.opacity(0.3), lineWidth: 1)

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .tint(ColorTheme.accentAI)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(ColorTheme.accentAI)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .frame(width: 36, height: 36)
        .scaleEffect(pulse ? 1.06 : 1)
        .shadow(color: ColorTheme.accentAI.opacity(pulse ? 0.45 : 0), radius: 12)
        .animation(pulseAnimation, value: pulse)
    }

    private var pulseAnimation: Animation {
        isProcessing
            ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
            : Motion.hover
    }

    private var promptField: some View {
        HStack(spacing: 10) {
            TextField("What would you like to brainstorm?", text: $inputText)
                .textFieldStyle(.plain)
                .foregroundStyle(ColorTheme.textPrimary)
                .font(.system(size: 15))
                .focused($inputFocused)
                .disabled(isProcessing)
                .onSubmit(handleGenerate)

            Button(action: handleGenerate) {
                Label(isProcessing ? "Thinking…" : "Generate", systemImage: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ColorTheme.accentAI)
            .disabled(isGenerateDisabled)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(ColorTheme.bgCardSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(promptFieldStroke, lineWidth: inputFocused ? 1.5 : 1)
        }
        .animation(Motion.hover, value: inputFocused)
    }

    private var promptFieldStroke: Color {
        inputFocused ? ColorTheme.accentAI.opacity(0.6) : ColorTheme.borderSubtle
    }

    private var isGenerateDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text("Runs on your Mac. Nothing leaves the device.")
                .font(.system(size: 11))
        }
        .foregroundStyle(ColorTheme.textMuted)
    }

    private var subtitle: String {
        if isProcessing {
            return "Building useful branches without leaving your Mac"
        }
        if let parentNode, !parentNode.title.isEmpty {
            return "Add focused branches beneath “\(parentNode.title)”"
        }
        return "Turn a topic into a clear, editable mind map"
    }

    private func handleGenerate() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isProcessing else { return }

        isProcessing = true
        inputFocused = false
        let parentNodeID = viewModel.generationParentNodeID

        generationTask = Task {
            await viewModel.generateIdeas(prompt: prompt, parentNodeID: parentNodeID)
            isProcessing = false
        }
    }

    private func cancel() {
        generationTask?.cancel()
        generationTask = nil
        isProcessing = false
        viewModel.cancelIdeaGeneration()
    }
}
