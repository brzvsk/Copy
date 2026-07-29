import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Hotkey recorders and the Launch at Login toggle. Launch at Login isn't part of
/// `SettingsStore` (it's not a UserDefaults value, it's the `SMAppService` login-item
/// registration), so this view owns its own local state and re-reads the service's
/// actual status after every attempted change rather than trusting the toggle's intent.
struct GeneralSettings: View {
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Copy:", name: .toggleShelf)
                KeyboardShortcuts.Recorder("Paste Stack:", name: .togglePasteStack)
                KeyboardShortcuts.Recorder("Quick Paste Latest:", name: .quickPasteLatest)
                KeyboardShortcuts.Recorder("Next Pinboard:", name: .nextPinboard)
            } footer: {
                Text("Quick Paste Latest pastes your most recent item into the current app without opening Copy. While the shelf is open, press a number key to paste that card.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
            } footer: {
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if launchAtLoginNeedsApproval {
                    Text("Waiting for approval in System Settings.")
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

    /// A toggle that reads back purely from `.status == .enabled` leaves the user with
    /// no explanation when macOS accepts `register()` but parks the login item pending
    /// approval in System Settings: the switch would just look off again with no clue
    /// why. `.requiresApproval` counts as "on" here (registration did succeed) with a
    /// footnote distinguishing that state from a plain, unregistered off.
    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
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
