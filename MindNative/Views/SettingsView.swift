import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel: Double = 1.0
    @AppStorage("autoLayoutEnabled") private var autoLayoutEnabled: Bool = true
    @AppStorage("showGrid") private var showGrid: Bool = true
    @AppStorage("snapToGrid") private var snapToGrid: Bool = false
    @AppStorage("gridSize") private var gridSize: Double = 24
    @AppStorage("preferredMapLayout") private var preferredMapLayout = MindMapLayout.horizontal.rawValue
    @StateObject private var updateService = UpdateService()

    var body: some View {
        TabView {
            Form {
                Section("Canvas view") {
                    LabeledContent("Default zoom") {
                        HStack(spacing: 12) {
                            Slider(value: $defaultZoomLevel, in: 0.5...2, step: 0.1)
                                .frame(width: 180)
                            Text("\(Int(defaultZoomLevel * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }

                    Toggle("Show Grid", isOn: $showGrid)
                        .help("Display a subtle alignment grid on the canvas")
                        .onChange(of: showGrid) { isVisible in
                            if !isVisible {
                                snapToGrid = false
                            }
                        }

                    Toggle("Snap to Grid", isOn: $snapToGrid)
                        .help("Snap nodes to grid when moving")
                        .disabled(!showGrid)

                    LabeledContent("Grid spacing") {
                        HStack(spacing: 12) {
                            Slider(value: $gridSize, in: 12...48, step: 4)
                                .frame(width: 180)
                            Text("\(Int(gridSize)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                    .disabled(!showGrid)
                }

                Section("Organization") {
                    Toggle("Auto Layout After Generation", isOn: $autoLayoutEnabled)
                        .help("Arrange generated branches automatically")

                    Text("AI generation runs on-device when Apple Intelligence is available. On other supported systems, MindNative creates a useful starter framework so the workflow never dead-ends.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Preferred layout", selection: $preferredMapLayout) {
                        ForEach(MindMapLayout.allCases) { style in
                            Label(style.title, systemImage: style.systemImage)
                                .tag(style.rawValue)
                        }
                    }
                }

                Section {
                    Button("Restore Defaults") {
                        restoreDefaults()
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("Ideas") {
                    VStack(alignment: .leading, spacing: 10) {
                        ShortcutRow(action: "Add Child Idea", shortcut: "Tab")
                        ShortcutRow(action: "Add Sibling Idea", shortcut: "Return")
                        ShortcutRow(action: "New Main Idea", shortcut: "⌥Return / N")
                        ShortcutRow(action: "Rename Idea", shortcut: "F2")
                        ShortcutRow(action: "Delete Node", shortcut: "Delete")
                        ShortcutRow(action: "Brainstorm with AI", shortcut: "⇧⌘G")
                        ShortcutRow(action: "Auto Layout", shortcut: "⌘L")
                    }
                    .padding(.vertical, 4)
                }

                Section("Selection") {
                    VStack(alignment: .leading, spacing: 10) {
                        ShortcutRow(action: "Select All", shortcut: "⌘A")
                        ShortcutRow(action: "Copy", shortcut: "⌘C")
                        ShortcutRow(action: "Cut", shortcut: "⌘X")
                        ShortcutRow(action: "Paste", shortcut: "⌘V")
                        ShortcutRow(action: "Duplicate", shortcut: "⌘D")
                    }
                    .padding(.vertical, 4)
                }

                Section("Navigation") {
                    VStack(alignment: .leading, spacing: 10) {
                        ShortcutRow(action: "Zoom In", shortcut: "⌘+")
                        ShortcutRow(action: "Zoom Out", shortcut: "⌘-")
                        ShortcutRow(action: "Actual Size", shortcut: "⌘0")
                        ShortcutRow(action: "Previous Node", shortcut: "⇧Tab")
                        ShortcutRow(action: "Navigate", shortcut: "Arrow Keys")
                        ShortcutRow(action: "Pan Canvas", shortcut: "⌥/Space + Drag")
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Shortcuts", systemImage: "keyboard")
            }

            Form {
                Section("Automation") {
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                    }

                    Text("Create maps, open a brainstorming flow, or export a Markdown outline from Shortcuts and Siri.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Updates") {
                    updateStatus

                    Button("Check for Updates") {
                        Task { await updateService.check() }
                    }
                    .disabled(updateService.state == .checking)
                }

                Section("Privacy") {
                    Text("MindNative stores maps locally and includes no advertising, tracking, or behavioral analytics.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Link(
                        "Privacy Policy",
                        destination: URL(
                            string: "https://github.com/SirwanAfifi/mindnative/blob/main/PRIVACY.md"
                        )!
                    )
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("System", systemImage: "macwindow.and.cursorarrow")
            }
        }
        .scenePadding()
        .frame(width: 520, height: 430)
    }

    private func restoreDefaults() {
        defaultZoomLevel = 1
        autoLayoutEnabled = true
        showGrid = true
        snapToGrid = false
        gridSize = 24
        preferredMapLayout = MindMapLayout.horizontal.rawValue
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateService.state {
        case .idle:
            Text("Updates are checked only when you ask.")
                .foregroundStyle(.secondary)
        case .checking:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
            }
        case .current:
            Label("MindNative is up to date.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let update):
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Version \(update.version) is available.",
                    systemImage: "arrow.down.circle.fill"
                )
                Button("View Release") {
                    updateService.open(update)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ColorTheme.bgCardSoft)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(ColorTheme.borderSubtle, lineWidth: 1)
                        }
                }
        }
    }
}

#Preview {
    SettingsView()
}
