import AppKit

/// CGEvent tap that intercepts a plain Command-V while the Paste Stack is active, so
/// pressing Command-V in any frontmost app walks the queue instead of pasting whatever
/// is already on the system pasteboard. Every event this tap sees passes straight
/// through except a bare Command-V (no Shift, no Option, no Control) that doesn't carry
/// our own `selfEventUserData` marker — that one is swallowed here; `AppCoordinator.pasteNextViaEngine()`
/// (wired as `onIntercept`) puts the next stack item on the pasteboard and re-synthesizes
/// a MARKED Command-V via `postMarkedPasteKeystroke()`, so the frontmost app still sees
/// what looks like an ordinary paste, and this tap lets that one through untouched.
///
/// Creating the tap requires Accessibility permission; `activate()` returns `false` when
/// the OS refuses (no permission, or Secure Input is active), in which case the caller
/// falls back to the `.pasteNextFromStack` hotkey.
final class PasteStackEngine {
    /// Marks a synthesized Command-V event as our own so the tap passes it straight
    /// through instead of re-intercepting it (which would loop forever).
    static let selfEventUserData: Int64 = 0xC0_50_11

    private let onIntercept: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onIntercept: @escaping () -> Void) {
        self.onIntercept = onIntercept
    }

    /// Creates and enables the event tap. Returns `false` when the tap couldn't be
    /// created — most commonly because Accessibility hasn't been granted — in which
    /// case the caller is expected to fall back to the `.pasteNextFromStack` hotkey.
    /// Safe to call again while already active (returns `true` without recreating it).
    @discardableResult
    func activate() -> Bool {
        if eventTap != nil { return true }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: (1 << CGEventType.keyDown.rawValue),
            callback: pasteStackEventTapCallback,
            userInfo: selfPointer
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    /// Disables and tears down the tap. Safe to call when already inactive (including
    /// repeatedly, e.g. from both the palette's close path and app termination).
    func deactivate() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        eventTap = nil
        runLoopSource = nil
    }

    /// Posts a Command-V keystroke marked with `selfEventUserData` so this tap (or any
    /// other Paste Stack engine instance) lets it straight through. Called by
    /// `AppCoordinator.pasteNextViaEngine()` once the next stack item is on the
    /// pasteboard, so the frontmost app receives what looks like an ordinary paste.
    /// Only used on the Accessibility-backed path — the `.pasteNextFromStack` fallback
    /// hotkey relies on the user's own ⌘V instead (see `AppCoordinator.pasteNextFromStack()`).
    static func postMarkedPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: selfEventUserData)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: selfEventUserData)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// The tap callback's actual logic, invoked by the C trampoline below. Runs on the
    /// main run loop (the source is added to `CFRunLoopGetMain()`), but stays lean per
    /// Apple's event-tap guidance — the real work happens in `onIntercept`, dispatched
    /// asynchronously so this callback returns immediately.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.selfEventUserData else {
            return Unmanaged.passUnretained(event) // our own synthesized ⌘V: pass through
        }

        let flags = event.flags
        let isPlainCommandV = flags.contains(.maskCommand)
            && event.getIntegerValueField(.keyboardEventKeycode) == 9
            && !flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
        guard isPlainCommandV else { return Unmanaged.passUnretained(event) }

        // Consume the original ⌘V; on main, place the next stack item on the
        // pasteboard, then synthesize a marked ⌘V so the frontmost app pastes it.
        DispatchQueue.main.async { [onIntercept] in onIntercept() }
        return nil
    }
}

/// C-callable trampoline for `CGEvent.tapCreate`. The callback type can't capture
/// state, so `userInfo` carries an unretained pointer to the engine instance instead.
private func pasteStackEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<PasteStackEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}
