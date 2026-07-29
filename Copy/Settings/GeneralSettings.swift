import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Hotkey recorders and the Launch at Login toggle. Launch at Login isn't part of
/// `SettingsStore` (it's not a UserDefaults value, it's the `SMAppService` login-item
/// registration), so this view owns its own local state and re-reads the service's
/// actual status after every attempted change rather than trusting the toggle's intent.
struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
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
                Picker("Shelf Size", selection: $settings.compactShelf) {
                    Text("Standard").tag(false)
                    Text("Compact").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Compact shows smaller cards so more fit in the shelf at once.")
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

            Section {
                Toggle("Hide the menu bar icon", isOn: $settings.hideMenuBarIcon)
                    .disabled(!shelfHotkeySet)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !shelfHotkeySet {
                        Text("Set the Open Copy shortcut above before hiding the menu bar icon.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Copy stays available with the Shift Command V shortcut. You can reach Settings and everything else from the shelf.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLaunchAtLoginStatus() }
    }

    /// The anti-stranding guard mirrored from `AppDelegate.applyHideMenuBarIconSetting`
    /// (the authoritative check): hiding the icon is only safe while the shelf summon
    /// hotkey is set, since it's the drawer-first model's other entry point once the
    /// icon is gone. Re-evaluated on every render (not cached in `@State`) so editing
    /// the "Open Copy" recorder above immediately un-disables this toggle.
    private var shelfHotkeySet: Bool {
        KeyboardShortcuts.getShortcut(for: .toggleShelf) != nil
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
