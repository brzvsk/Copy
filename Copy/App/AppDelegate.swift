import AppKit
import CopyCore
import KeyboardShortcuts
import Quartz
import Sparkle

extension KeyboardShortcuts.Name {
    static let toggleShelf = Self("toggleShelf", initial: .init(.v, modifiers: [.command, .shift]))
    static let togglePasteStack = Self("togglePasteStack", initial: .init(.c, modifiers: [.command, .shift]))
    static let pasteNextFromStack = Self("pasteNextFromStack", initial: .init(.n, modifiers: [.control, .option, .command]))
    /// No default shortcut — the user opts in from Settings. Pastes the most recent
    /// history item directly into the frontmost app without opening the shelf.
    static let quickPasteLatest = Self("quickPasteLatest")
    /// No default shortcut — the user opts in from Settings. Advances the shelf's
    /// active tab to the next pinboard while the shelf is open.
    static let nextPinboard = Self("nextPinboard")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Optional so `SettingsStore.hideMenuBarIcon` can remove it live — see
    /// `applyHideMenuBarIconSetting`. `nil` means no status item exists right now.
    private var statusItem: NSStatusItem?
    private var coordinator: AppCoordinator!
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                                   updaterDelegate: nil,
                                                                   userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            coordinator = try AppCoordinator()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Copy could not open its database"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        applyHideMenuBarIconSetting(coordinator.settings.hideMenuBarIcon)
        coordinator.settings.onHideMenuBarIconChange = { [weak self] hide in
            self?.applyHideMenuBarIconSetting(hide)
        }
        // Third trigger for the anti-stranding guard: `hideMenuBarIcon` itself doesn't
        // change when the user clears the shelf summon hotkey from Settings, so
        // `onHideMenuBarIconChange` above never fires for that edit. Without this,
        // hiding the icon and then clearing the hotkey in the same session would leave
        // the user with neither the icon nor the hotkey — re-running the guard here
        // (it re-reads `KeyboardShortcuts.getShortcut` itself) restores the icon in
        // that case. See `SettingsStore.onShelfHotkeyChange`'s doc comment.
        coordinator.settings.onShelfHotkeyChange = { [weak self] in
            guard let self else { return }
            self.applyHideMenuBarIconSetting(self.coordinator.settings.hideMenuBarIcon)
        }

        coordinator.start()

        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            coordinator.showOnboarding()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleShelf) { [weak self] in
            self?.coordinator.toggleShelf()
        }
        KeyboardShortcuts.onKeyDown(for: .togglePasteStack) { [weak self] in
            self?.coordinator.togglePasteStack()
        }
        // Fallback path only: `AppCoordinator` enables this while the Paste Stack is
        // active and the CGEvent tap couldn't be created (no Accessibility), and
        // disables it again on deactivation — see `pasteStackModel.onActiveChange`.
        KeyboardShortcuts.onKeyDown(for: .pasteNextFromStack) { [weak self] in
            self?.coordinator.pasteNextFromStack()
        }
        KeyboardShortcuts.disable(.pasteNextFromStack)
        KeyboardShortcuts.onKeyDown(for: .quickPasteLatest) { [weak self] in
            self?.coordinator.quickPasteLatest()
        }
        KeyboardShortcuts.onKeyDown(for: .nextPinboard) { [weak self] in
            self?.coordinator.selectNextPinboard()
        }

        // Bridged directly here rather than through `AppCoordinator`: the Sparkle
        // updater controller and `NSApp` are both owned/reachable at this layer, not
        // the coordinator's.
        coordinator.shelfViewModel.onCheckForUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
        coordinator.shelfViewModel.onQuit = {
            NSApp.terminate(nil)
        }
    }

    /// Creates or removes the status item to honor `SettingsStore.hideMenuBarIcon`.
    /// Called at launch, live via `onHideMenuBarIconChange` (the setting itself
    /// flipping), and live via `onShelfHotkeyChange` (the shelf hotkey changing while
    /// the setting stays put) — three triggers feeding one authoritative check, so the
    /// guard below can't go stale under either kind of edit.
    ///
    /// Anti-stranding guard: hiding the icon must never leave the user with no way to
    /// reach Copy. The shelf's summon hotkey (`KeyboardShortcuts.Name.toggleShelf`,
    /// ⇧⌘V by default) is drawer-first's other entry point, so this refuses to honor
    /// `hide` — keeping the status item visible regardless — if that hotkey is unset.
    /// `GeneralSettings` mirrors this by disabling its "Hide the menu bar icon" toggle
    /// under the same condition, but this check is the actually-authoritative one.
    private func applyHideMenuBarIconSetting(_ hide: Bool) {
        let canHide = hide && KeyboardShortcuts.getShortcut(for: .toggleShelf) != nil
        if canHide {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        } else if statusItem == nil {
            createStatusItem()
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                     accessibilityDescription: "Copy")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.applicationWillTerminate()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open Copy", action: #selector(openShelf), keyEquivalent: "V")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)
        let newItem = NSMenuItem(title: "New Item…", action: #selector(createItem), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)
        menu.addItem(.separator())

        let items = coordinator.recentItems()
        if items.isEmpty {
            let empty = NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in items {
            let menuItem = NSMenuItem(title: item.displayTitle,
                                      action: #selector(pasteMenuItem(_:)),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())
        let pause = NSMenuItem(title: coordinator.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let export = NSMenuItem(title: "Export…", action: #selector(exportHistory), keyEquivalent: "")
        export.target = self
        menu.addItem(export)
        let importItem = NSMenuItem(title: "Import…", action: #selector(importHistory), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let pasteStack = NSMenuItem(title: "Paste Stack", action: #selector(togglePasteStack), keyEquivalent: "c")
        pasteStack.keyEquivalentModifierMask = [.command, .shift]
        pasteStack.target = self
        pasteStack.state = coordinator.isPasteStackActive ? .on : .off
        menu.addItem(pasteStack)
        let checkForUpdates = NSMenuItem(title: "Check for Updates…",
                                         action: #selector(checkForUpdates(_:)),
                                         keyEquivalent: "")
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Copy",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    @objc private func openShelf() {
        coordinator.toggleShelf()
    }

    @objc private func createItem() {
        coordinator.newItem()
    }

    @objc private func pasteMenuItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipItem else { return }
        coordinator.paste(item)
    }

    @objc private func togglePause() {
        coordinator.togglePause()
    }

    @objc private func exportHistory() {
        coordinator.exportHistory()
    }

    @objc private func importHistory() {
        coordinator.importHistory()
    }

    @objc private func openSettings() {
        coordinator.openSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    @objc private func togglePasteStack() {
        coordinator.togglePasteStack()
    }

    @objc private func clearHistory() {
        coordinator.confirmAndClearHistory()
    }
}

// MARK: - Quick Look panel control

/// `AppDelegate` is always reachable via `NSApp.delegate`, so it's a reliable place to
/// implement Quick Look's responder-chain "who controls the panel" trio — these three
/// methods are an informal `NSObject` category (not a protocol Swift enforces), called
/// by AppKit whenever `QLPreviewPanel` re-resolves its controller (e.g. as it becomes
/// key). `QuickLookController.preview(_:)` already sets `dataSource`/`delegate`
/// directly before showing the panel; this extension just keeps that assignment
/// correct if AppKit re-runs its own controller search afterward.
extension AppDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        QuickLookController.shared.hasContent
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        QuickLookController.shared.clear()
    }
}
