import SwiftUI

/// Retention window and link-preview fetching, both persisted through `SettingsStore`.
struct HistorySettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                StepSlider(labels: RetentionPeriod.sliderOrder.map(\.title), index: retentionIndex)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            } header: {
                Text("Keep History")
            } footer: {
                Text(retentionFooter)
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

            Section {
                Toggle("Recognize Text in Images", isOn: $settings.recognizeImageText)
            } footer: {
                Text("Copy reads text in copied images so you can search and copy it. This runs entirely on your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Bridges the `StepSlider`'s `Int` position to the stored `RetentionPeriod`, using the
    /// shortest-to-longest `sliderOrder`. Falls back to the last stop (Unlimited) if the
    /// stored value somehow isn't in the order.
    private var retentionIndex: Binding<Int> {
        let order = RetentionPeriod.sliderOrder
        return Binding(
            get: { order.firstIndex(of: settings.retention) ?? order.count - 1 },
            set: { settings.retention = order[$0] }
        )
    }

    private var retentionFooter: String {
        if settings.retention == .unlimited {
            return "Nothing is removed by age. Favorites and pinboard items are always kept."
        }
        return "Items you haven't used in \(settings.retention.title.lowercased()) are removed. Favorites and pinboard items are always kept."
    }
}
