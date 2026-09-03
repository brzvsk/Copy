import CopyCore
import SwiftUI

/// The History pane's storage block: a total, a proportional stacked bar, per-type rows
/// (with a per-type "Clear"), and a prominent "Clear History" button. Reads
/// `ItemStore.storageBreakdown()` (the clearable set excludes pinboard items) and clears through the store,
/// which the shelf observes live via GRDB, so an open shelf refreshes on its own.
struct StorageUsageSection: View {
    let store: ItemStore

    @State private var usage: [StorageUsage] = []
    @State private var confirmClearAll = false
    @State private var pendingKindClear: StorageCategory?

    var body: some View {
        Group {
            Section {
                if categories.isEmpty {
                    Text("No clearable history")
                        .foregroundStyle(.secondary)
                } else {
                    summary
                    ForEach(categories) { row($0) }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Pinboard items are kept and aren't counted here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !categories.isEmpty {
                Section {
                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        HStack {
                            Text("Clear History")
                            Spacer()
                            Text(byteString(totalBytes))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClearAll) {
            Button("Clear History", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinboard items are kept. This cannot be undone.")
        }
        .confirmationDialog(
            pendingKindClear.map { "Clear all \($0.label.lowercased()) from history?" } ?? "",
            isPresented: pendingKindClearShown,
            presenting: pendingKindClear
        ) { category in
            Button("Clear \(category.label)", role: .destructive) { clear(category: category) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Pinboard items are kept. This cannot be undone.")
        }
    }

    // MARK: Pieces

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(totalCount) \(totalCount == 1 ? "item" : "items")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(byteString(totalBytes))
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            StackedBar(segments: categories.map { ($0.category.color, Double($0.bytes)) })
                .frame(height: 8)
        }
        .padding(.vertical, 4)
    }

    private func row(_ usage: CategoryUsage) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(usage.category.color)
                .frame(width: 10, height: 10)
            Text(usage.category.label)
            Spacer(minLength: 8)
            Text("\(usage.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(byteString(usage.bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 62, alignment: .trailing)
            IconButton(systemName: "trash", fontSize: 11,
                       size: CGSize(width: 24, height: 22),
                       help: "Clear \(usage.category.label)") {
                pendingKindClear = usage.category
            }
        }
    }

    // MARK: Data

    private var categories: [CategoryUsage] {
        let byKind = Dictionary(usage.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        return StorageCategory.allCases.compactMap { category in
            let rows = category.kinds.compactMap { byKind[$0] }
            let count = rows.reduce(0) { $0 + $1.count }
            let bytes = rows.reduce(0) { $0 + $1.bytes }
            guard count > 0 else { return nil }
            return CategoryUsage(category: category, count: count, bytes: bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private var totalBytes: Int { categories.reduce(0) { $0 + $1.bytes } }
    private var totalCount: Int { categories.reduce(0) { $0 + $1.count } }

    private var pendingKindClearShown: Binding<Bool> {
        Binding(get: { pendingKindClear != nil }, set: { if !$0 { pendingKindClear = nil } })
    }

    private func reload() {
        usage = (try? store.storageBreakdown()) ?? []
    }

    private func clearAll() {
        try? store.clearHistory()
        reload()
    }

    private func clear(category: StorageCategory) {
        for kind in category.kinds {
            try? store.clearHistory(kind: kind)
        }
        reload()
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// One aggregated display row: a category and its summed count/bytes.
private struct CategoryUsage: Identifiable {
    let category: StorageCategory
    let count: Int
    let bytes: Int
    var id: StorageCategory { category }
}

/// Display buckets for the storage breakdown, mirroring `ShelfScope`'s categories (Text
/// folds in rich text) with a distinct color per bucket.
enum StorageCategory: String, CaseIterable, Identifiable, Hashable {
    case text, links, images, files, colors

    var id: String { rawValue }

    var kinds: [ItemKind] {
        switch self {
        case .text: return [.text, .richText]
        case .links: return [.link]
        case .images: return [.image]
        case .files: return [.file]
        case .colors: return [.color]
        }
    }

    var label: String {
        switch self {
        case .text: return "Text"
        case .links: return "Links"
        case .images: return "Images"
        case .files: return "Files"
        case .colors: return "Colors"
        }
    }

    var color: Color {
        switch self {
        case .text: return .blue
        case .links: return .teal
        case .images: return .orange
        case .files: return .green
        case .colors: return .purple
        }
    }
}

/// A slim horizontal bar split into proportional colored segments, clipped to a capsule.
struct StackedBar: View {
    let segments: [(color: Color, value: Double)]

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segment.color
                        .frame(width: geo.size.width * segment.value / total)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(Capsule())
        .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4)))
    }
}
