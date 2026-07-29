import SwiftUI

/// Root content of the SwiftUI `Settings` scene: three tabs backed by the shared
/// `SettingsStore` (see `AppCoordinator.settings`).
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
