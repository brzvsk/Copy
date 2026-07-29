import AppKit

/// Logs every save failure; alerts the user once per launch so failures are never silent.
final class SaveErrorReporter {
    private var alerted = false

    func report(_ error: Error) {
        NSLog("Copy: failed to save clipboard item: \(error)")
        DispatchQueue.main.async {
            guard !self.alerted else { return }
            self.alerted = true
            let alert = NSAlert()
            alert.messageText = "Copy can't save clipboard history"
            alert.informativeText = "New items are not being recorded. \(error.localizedDescription)"
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
