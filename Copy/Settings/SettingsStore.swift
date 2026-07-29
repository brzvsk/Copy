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
    static let recognizeImageTextKey = "recognizeImageText"
    static let excludedBundleIDsKey = "excludedBundleIDs"
    static let hideDuringScreenSharingKey = "hideDuringScreenSharing"
    static let compactShelfKey = "compactShelf"
    static let hideMenuBarIconKey = "hideMenuBarIcon"

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

    var recognizeImageText: Bool {
        didSet {
            guard recognizeImageText != oldValue else { return }
            defaults.set(recognizeImageText, forKey: Self.recognizeImageTextKey)
        }
    }

    var excludedBundleIDs: [String] {
        didSet {
            guard excludedBundleIDs != oldValue else { return }
            persistExcludedBundleIDs()
            onRulesChange?(Set(excludedBundleIDs))
        }
    }

    /// When true, the shelf panel and Paste Stack palette set `NSWindowSharingType.none`
    /// so they're excluded from screen recordings/captures/shares (see
    /// `ShelfPanelController.setHideDuringScreenSharing`/`PasteStackController`'s
    /// equivalent). Defaults to false: Copy is visible in screenshots and recordings
    /// out of the box (so people can capture and share it), and hiding is opt-in.
    var hideDuringScreenSharing: Bool {
        didSet {
            guard hideDuringScreenSharing != oldValue else { return }
            defaults.set(hideDuringScreenSharing, forKey: Self.hideDuringScreenSharingKey)
            onHideDuringScreenSharingChange?(hideDuringScreenSharing)
        }
    }

    /// Narrower/shorter cards and a shorter shelf panel, so more items fit at a glance.
    /// `ShelfRootView`/`ItemCardView` read this live (via `ShelfViewModel.settings`,
    /// since both are `@Observable`), and `onCompactShelfChange` pushes it to
    /// `ShelfPanelController` so the panel's own frame height adapts, mirroring
    /// `hideDuringScreenSharing`'s wiring above.
    var compactShelf: Bool {
        didSet {
            guard compactShelf != oldValue else { return }
            defaults.set(compactShelf, forKey: Self.compactShelfKey)
            onCompactShelfChange?(compactShelf)
        }
    }

    /// When true, `AppDelegate` removes the `NSStatusItem` so Copy runs with no menu
    /// bar icon at all, relying on the shelf's own drawer menu (and the shelf summon
    /// hotkey) instead. Defaults to false: the icon is shown out of the box, and
    /// going menu-bar-free is opt-in. `AppDelegate` applies an anti-stranding guard on
    /// top of this value — it refuses to actually hide the icon if the shelf summon
    /// hotkey is unset — so this property alone doesn't guarantee the icon is hidden.
    var hideMenuBarIcon: Bool {
        didSet {
            guard hideMenuBarIcon != oldValue else { return }
            defaults.set(hideMenuBarIcon, forKey: Self.hideMenuBarIconKey)
            onHideMenuBarIconChange?(hideMenuBarIcon)
        }
    }

    @ObservationIgnored var onRulesChange: ((Set<String>) -> Void)?
    @ObservationIgnored var onHideDuringScreenSharingChange: ((Bool) -> Void)?
    @ObservationIgnored var onCompactShelfChange: ((Bool) -> Void)?
    @ObservationIgnored var onHideMenuBarIconChange: ((Bool) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.retentionKey), let period = RetentionPeriod(rawValue: raw) {
            retention = period
        } else {
            retention = .unlimited
        }
        fetchLinkPreviews = (defaults.object(forKey: Self.fetchLinkPreviewsKey) as? Bool) ?? true
        recognizeImageText = (defaults.object(forKey: Self.recognizeImageTextKey) as? Bool) ?? true
        hideDuringScreenSharing = (defaults.object(forKey: Self.hideDuringScreenSharingKey) as? Bool) ?? false
        compactShelf = (defaults.object(forKey: Self.compactShelfKey) as? Bool) ?? false
        hideMenuBarIcon = (defaults.object(forKey: Self.hideMenuBarIconKey) as? Bool) ?? false
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
