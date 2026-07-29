import AppKit
import CopyCore
import UniformTypeIdentifiers

/// Export/import of the full clipboard history and pinboards to/from a single JSON
/// backup file (see `ArchiveIO` in CopyCore), driven by the status menu's
/// "Export…"/"Import…" actions.
@MainActor
final class ArchiveController {
    private let store: ItemStore
    private let pinboardStore: PinboardStore
    private let queue = DispatchQueue(label: "com.tarikbc.copy.archive", qos: .userInitiated)

    init(store: ItemStore, pinboardStore: PinboardStore) {
        self.store = store
        self.pinboardStore = pinboardStore
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Copy-export-\(Self.dateStamp()).json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let store = self.store
        let pinboardStore = self.pinboardStore
        queue.async {
            do {
                let data = try ArchiveIO.export(items: store, pinboards: pinboardStore)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    HUD.show("Exported")
                }
            } catch {
                NSLog("Copy: export failed: \(error)")
                DispatchQueue.main.async {
                    HUD.show("Export failed")
                }
            }
        }
    }

    func importHistory() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let store = self.store
        let pinboardStore = self.pinboardStore
        queue.async {
            do {
                let data = try Data(contentsOf: url)
                let result = try ArchiveIO.importArchive(data, into: store, pinboards: pinboardStore)
                DispatchQueue.main.async {
                    let noun = result.itemsAdded == 1 ? "item" : "items"
                    HUD.show("Imported \(result.itemsAdded) \(noun)")
                }
            } catch {
                NSLog("Copy: import failed: \(error)")
                DispatchQueue.main.async {
                    HUD.show("Import failed")
                }
            }
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
