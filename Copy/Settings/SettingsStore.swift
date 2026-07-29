import Foundation
import Observation

/// How long unfavorited, unpinned history items are kept before pruning.
enum RetentionPeriod: String, CaseIterable {
    case unlimited
    case day
    case week
    case month
    case threeMonths

    /// The earliest `lastUsedAt` to keep; `nil` means keep everything.
    var cutoff: Date? {
        let now = Date()
        switch self {
        case .unlimited:
            return nil
        case .day:
            return Calendar.current.date(byAdding: .day, value: -1, to: now)
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            return Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            return Calendar.current.date(byAdding: .month, value: -3, to: now)
        }
    }

    var title: String {
        switch self {
        case .unlimited: return "Unlimited"
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .threeMonths: return "3 Months"
        }
    }
}

/// UserDefaults-backed app settings. Mutating `excludedBundleIDs` (directly or via
/// `addExcludedApp`/`removeExcludedApp`) fires `onRulesChange` so the coordinator can
/// push a fresh `RulesEngine` into the clipboard monitor.
@MainActor
@Observable
final class SettingsStore {
    static let retentionKey = "retentionPeriod"
    static let fetchLinkPreviewsKey = "fetchLinkPreviews"
    static let excludedBundleIDsKey = "excludedBundleIDs"

    var retention: RetentionPeriod {
        didSet {
            guard retention != oldValue else { return }
            defaults.set(retention.rawValue, forKey: Self.retentionKey)
        }
    }

    var fetchLinkPreviews: Bool {
        didSet {
            guard fetchLinkPreviews != oldValue else { return }
            defaults.set(fetchLinkPreviews, forKey: Self.fetchLinkPreviewsKey)
        }
    }

    var excludedBundleIDs: [String] {
        didSet {
            guard excludedBundleIDs != oldValue else { return }
            persistExcludedBundleIDs()
            onRulesChange?(Set(excludedBundleIDs))
        }
    }

    @ObservationIgnored var onRulesChange: ((Set<String>) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.retentionKey), let period = RetentionPeriod(rawValue: raw) {
            retention = period
        } else {
            retention = .unlimited
        }
        fetchLinkPreviews = (defaults.object(forKey: Self.fetchLinkPreviewsKey) as? Bool) ?? true
        if let data = defaults.data(forKey: Self.excludedBundleIDsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            excludedBundleIDs = decoded.sorted()
        } else {
            excludedBundleIDs = []
        }
    }

    func addExcludedApp(bundleID: String) {
        guard !excludedBundleIDs.contains(bundleID) else { return }
        excludedBundleIDs = (excludedBundleIDs + [bundleID]).sorted()
    }

    func removeExcludedApp(bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    private func persistExcludedBundleIDs() {
        guard let data = try? JSONEncoder().encode(excludedBundleIDs) else { return }
        defaults.set(data, forKey: Self.excludedBundleIDsKey)
    }
}
