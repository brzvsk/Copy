import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Hotkey recorders and the Launch at Login toggle. Launch at Login isn't part of
/// `SettingsStore` (it's not a UserDefaults value, it's the `SMAppService` login-item
/// registration), so this view owns its own local state and re-reads the service's
/// actual status after every attempted change rather than trusting the toggle's intent.
struct GeneralSettings: View {
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Copy:", name: .toggleShelf)
                KeyboardShortcuts.Recorder("Paste Stack:", name: .togglePasteStack)
            }

            Section {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
            } footer: {
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLaunchAtLoginStatus() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Couldn't update Launch at Login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }
}
