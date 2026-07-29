import SwiftUI

/// Root content of the SwiftUI `Settings` scene: three tabs backed by the shared
/// `SettingsStore` (see `AppCoordinator.settings`).
///
/// M7: deliberately NOT adopting `glassSurface` anywhere in this view or its three
/// panes (`GeneralSettings`, `HistorySettings`, `PrivacySettings`). Unlike the shelf,
/// paste stack, and popovers/sheets, Settings hosts in a plain titled `NSWindow`
/// (`SettingsWindowController`) with no visual-effect material of its own, and its
/// content is `Form(.formStyle(.grouped))` — a system control that already draws its
/// own section chrome. Backing that in glass would fight the grouped form's own
/// background rather than read as one intentional surface, and Apple's own System
/// Settings app keeps its form content on the opaque window background rather than
/// glass on macOS 26 (glass there is reserved for chrome like the sidebar, not the
/// settings content itself — same reasoning as `ItemCardView`). The task brief called
/// this surface "optional and lower-value"; this is that "note if you skip."
struct SettingsView: View {
    let settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            HistorySettings(settings: settings)
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            PrivacySettings(settings: settings)
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .frame(width: 480)
    }
}
