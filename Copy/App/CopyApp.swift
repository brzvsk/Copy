import SwiftUI

@main
struct CopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The real Settings window is `SettingsWindowController`, shown by
    // `AppCoordinator.openSettings()`. This placeholder scene only exists because
    // `App` requires at least one `Scene`; see `SettingsWindowController` for why
    // Copy doesn't use SwiftUI's `Settings` scene as the actual mechanism.
    var body: some Scene {
        Settings { EmptyView() }
            // SwiftUI still installs its standard ⌘, command for the placeholder
            // scene above. Replace that command so it opens the real AppKit-owned
            // settings window instead of presenting an empty scene.
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        appDelegate.openSettingsFromCommand()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
