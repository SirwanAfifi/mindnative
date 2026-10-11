import SwiftUI
import AppIntents

@main
struct MindNativeApp: App {
    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            MindNativeShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: MindDocument()) { file in
            NavigationStack {
                CanvasView(
                    document: file.$document,
                    fileURL: file.fileURL
                )
            }
            .tint(ColorTheme.accentPrimary)
            .frame(minWidth: 760, minHeight: 520)
            .onOpenURL { url in
                guard url.scheme == "mindnative",
                      url.host == "brainstorm" else {
                    return
                }
                let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
                AppIntentRouter.shared.pendingBrainstormPrompt = components?
                    .queryItems?
                    .first(where: { $0.name == "topic" })?
                    .value ?? ""
            }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
