import SwiftUI

/// Retention window and link-preview fetching, both persisted through `SettingsStore`.
struct HistorySettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Keep History:", selection: $settings.retention) {
                    ForEach(RetentionPeriod.allCases, id: \.self) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Favorites and pinboard items are always kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Fetch Link Previews", isOn: $settings.fetchLinkPreviews)
            } footer: {
                Text("Copy loads titles and icons for copied links from the web.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
