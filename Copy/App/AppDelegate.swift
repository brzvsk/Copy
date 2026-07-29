import AppKit
import CopyCore
import KeyboardShortcuts
import Quartz
import Sparkle

extension KeyboardShortcuts.Name {
    static let toggleShelf = Self("toggleShelf", initial: .init(.v, modifiers: [.command, .shift]))
    static let togglePasteStack = Self("togglePasteStack", initial: .init(.v, modifiers: [.control, .option, .command]))
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
    private var statusItem: NSStatusItem!
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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "Copy")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

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
        let pasteStack = NSMenuItem(title: "Paste Stack", action: #selector(togglePasteStack), keyEquivalent: "v")
        pasteStack.keyEquivalentModifierMask = [.control, .option, .command]
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
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Favorites are kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            coordinator.clearHistory()
        }
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
