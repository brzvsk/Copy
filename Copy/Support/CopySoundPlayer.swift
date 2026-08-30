import AppKit

extension Notification.Name {
    /// Posted after Copy itself successfully places a selected shelf item on the
    /// pasteboard. The clipboard monitor ignores that marked write, so this separate
    /// event avoids both missed feedback and double playback.
    static let copyDidCompleteInternalCopy = Notification.Name(
        "com.tarikbc.copy.didCompleteInternalCopy")
}

/// Small cached player for optional clipboard-capture feedback. `NSSound` is enough for
/// these sub-second bundled WAVs and follows the user's system output device and volume.
@MainActor
final class CopySoundPlayer {
    static let shared = CopySoundPlayer()

    private var cache: [CopySound: NSSound] = [:]
    private var playing: NSSound?
    private var internalCopyObserver: NSObjectProtocol?

    private init() {
        internalCopyObserver = NotificationCenter.default.addObserver(
            forName: .copyDidCompleteInternalCopy,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.playPersistedSelection()
            }
        }
    }

    func play(_ choice: CopySound) {
        playing?.stop()
        playing = nil

        guard let resourceName = choice.resourceName else { return }
        let sound: NSSound
        if let cached = cache[choice] {
            sound = cached
        } else {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "wav"),
                  let loaded = NSSound(contentsOf: url, byReference: false) else { return }
            cache[choice] = loaded
            sound = loaded
        }

        playing = sound
        sound.play()
    }

    private func playPersistedSelection() {
        let choice = UserDefaults.standard.string(forKey: SettingsStore.copySoundKey)
            .flatMap(CopySound.init(rawValue:)) ?? .off
        play(choice)
    }
}
