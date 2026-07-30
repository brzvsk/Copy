import AppKit
import SwiftUI

/// The About pane: app identity (icon + version), a Sparkle update check, and project
/// links. Leads with a centered identity block instead of the standard `SettingsPaneHeader`
/// the other panes use, the way an about box conventionally looks. "Check for Updates…"
/// routes through `SettingsStore.onCheckForUpdates` (wired to Sparkle in `AppDelegate`) so
/// this view never reaches into the updater directly.
struct AboutSettings: View {
    @Bindable var settings: SettingsStore

    private static let repoURL = URL(string: "https://github.com/tarikbc/Copy")!
    private static let issuesURL = URL(string: "https://github.com/tarikbc/Copy/issues/new")!
    private static let licenseURL = URL(string: "https://github.com/tarikbc/Copy/blob/main/LICENSE")!

    var body: some View {
        VStack(spacing: 0) {
            identity
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 6)

            Form {
                Section {
                    Button("Check for Updates…") { settings.onCheckForUpdates?() }
                    Button("View Onboarding Again") { settings.onShowOnboarding?() }
                }

                Section {
                    Button("View on GitHub") { NSWorkspace.shared.open(Self.repoURL) }
                    Button("Report an Issue") { NSWorkspace.shared.open(Self.issuesURL) }
                    Button("License (GPL-3.0)") { NSWorkspace.shared.open(Self.licenseURL) }
                } footer: {
                    Text("© 2026 Tarik Caramanico · GPL-3.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Copy")
                .font(.system(size: 20, weight: .semibold))
            Text(versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A visual shelf for your clipboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}
