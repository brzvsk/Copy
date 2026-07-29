import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Excluded-apps management: Copy never captures clipboard content while one of these
/// apps is frontmost (enforced by `RulesEngine`, pushed by `SettingsStore.onRulesChange`).
struct PrivacySettings: View {
    @Bindable var settings: SettingsStore
    @State private var selectedBundleID: String?

    var body: some View {
        Form {
            Section {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                } else {
                    List(settings.excludedBundleIDs, id: \.self, selection: $selectedBundleID) { bundleID in
                        excludedAppRow(bundleID)
                    }
                    .frame(minHeight: 160)
                }

                HStack(spacing: 8) {
                    Button {
                        addExcludedApp()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add App")

                    Button {
                        removeSelectedApp()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .accessibilityLabel("Remove App")
                    .disabled(selectedBundleID == nil)

                    Spacer()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Copy never records concealed content from password managers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func excludedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let icon = AppIconCache.icon(forBundleID: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(forBundleID: bundleID))
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        settings.addExcludedApp(bundleID: bundleID)
    }

    private func removeSelectedApp() {
        guard let selectedBundleID else { return }
        settings.removeExcludedApp(bundleID: selectedBundleID)
        self.selectedBundleID = nil
    }
}
