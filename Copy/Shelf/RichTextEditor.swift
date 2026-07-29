import AppKit
import SwiftUI

/// Bridges toolbar commands (Bold/Italic/Underline/Strikethrough) and live stats
/// between `EditItemSheet`'s SwiftUI controls and the `NSTextView` that `RichTextEditor`
/// owns internally. A SwiftUI toolbar can't reach into an `NSViewRepresentable`'s
/// underlying view directly, so `RichTextEditor` hands its text view to this controller
/// in `makeNSView`, and the sheet drives formatting/reads stats through the controller
/// instead of holding an `NSTextView` reference itself.
@MainActor
final class RichTextEditorController: ObservableObject {
    @Published private(set) var characterCount = 0
    @Published private(set) var wordCount = 0
    @Published private(set) var lineCount = 1

    /// Whether the current selection (or, for an empty selection/caret, the typing
    /// attributes the next character would inherit) is already bold/italic/underlined/
    /// struck through — drives the toolbar's active-state highlight. Read-only: only
    /// `refreshActiveState()` writes these, and it never mutates the text view.
    @Published private(set) var isBoldActive = false
    @Published private(set) var isItalicActive = false
    @Published private(set) var isUnderlineActive = false
    @Published private(set) var isStrikethroughActive = false

    fileprivate weak var textView: NSTextView?

    /// Bold/Italic are font *traits*, not standalone attributes — `NSTextView` has no
    /// callable `toggleBold(_:)`/`toggleItalic(_:)` member (those only exist as
    /// informal Font-menu action selectors forwarded through `NSFontManager`, not as
    /// methods on the class itself), so this converts the font at each affected
    /// character via `NSFontManager.shared`, matching what the Font panel's Bold/Italic
    /// checkboxes do under the hood.
    func toggleBold() {
        toggleFontTrait(.boldFontMask)
        refreshActiveState()
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
        refreshActiveState()
    }

    /// Underline and Strikethrough are plain character attributes (`.underlineStyle` /
    /// `.strikethroughStyle`), applied/removed by hand — on the selected range when
    /// there is one, otherwise on `typingAttributes` so the next characters typed pick
    /// it up.
    func toggleUnderline() {
        toggleStyleAttribute(.underlineStyle)
        refreshActiveState()
    }

    func toggleStrikethrough() {
        toggleStyleAttribute(.strikethroughStyle)
        refreshActiveState()
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let fontManager = NSFontManager.shared
        let range = textView.selectedRange()
        let fallback = textView.font ?? NSFont.systemFont(ofSize: 13)

        if range.length > 0, let storage = textView.textStorage {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? fallback
                let hasTrait = fontManager.traits(of: font).contains(trait)
                let updated = hasTrait
                    ? fontManager.convert(font, toNotHaveTrait: trait)
                    : fontManager.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: updated, range: subrange)
            }
            storage.endEditing()
            textView.didChangeText()
        } else {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? fallback
            let hasTrait = fontManager.traits(of: font).contains(trait)
            let updated = hasTrait
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
            var attrs = textView.typingAttributes
            attrs[.font] = updated
            textView.typingAttributes = attrs
        }
    }

    private func toggleStyleAttribute(_ key: NSAttributedString.Key) {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard range.length > 0, let storage = textView.textStorage else {
            var attrs = textView.typingAttributes
            let isOn = ((attrs[key] as? Int) ?? 0) != 0
            attrs[key] = isOn ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
            return
        }
        let isOn = ((storage.attribute(key, at: range.location, effectiveRange: nil) as? Int) ?? 0) != 0
        storage.beginEditing()
        if isOn {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func updateStats(from text: NSAttributedString) {
        let plain = text.string
        characterCount = plain.count
        wordCount = plain.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        lineCount = plain.components(separatedBy: .newlines).count
    }

    /// Recomputes the toolbar's active-state flags from the attributes at the current
    /// selection's start, or `typingAttributes` for an empty selection/caret (the same
    /// source `toggleFontTrait`/`toggleStyleAttribute` read from). This is a
    /// simplification for a mixed selection (part bold, part not) — it reflects the
    /// attribute at the selection's start rather than computing a tri-state "mixed"
    /// indicator, which matches what a click on the toolbar button would toggle from
    /// (`toggleFontTrait` also only inspects/converts per-run, so this is consistent
    /// with the toggle's own behavior, just not a full mixed-state UI).
    func refreshActiveState() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let attrs: [NSAttributedString.Key: Any]
        if range.length > 0, let storage = textView.textStorage, range.location < storage.length {
            attrs = storage.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }
        let font = (attrs[.font] as? NSFont) ?? textView.font ?? NSFont.systemFont(ofSize: 13)
        let traits = NSFontManager.shared.traits(of: font)
        isBoldActive = traits.contains(.boldFontMask)
        isItalicActive = traits.contains(.italicFontMask)
        isUnderlineActive = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
        isStrikethroughActive = ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0
    }
}

/// `NSViewRepresentable` wrapping a rich-editing `NSTextView` inside an `NSScrollView`.
/// SwiftUI's `AttributedString`-backed `TextEditor` binding needs macOS 26; on this
/// app's macOS 14 floor, rich editing goes through `NSTextView` directly instead — its
/// rich-text mode, `NSAttributedString` storage, `NSFontManager` trait conversion, and
/// character-attribute editing all predate 14, so nothing here needs an availability
/// gate except Writing Tools (see `makeNSView`).
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let controller: RichTextEditorController

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attributedText)

        // Writing Tools (proofread/rewrite) is macOS 15+; `NSTextView` picks it up
        // automatically once rich-text editing is enabled — this just requests the full
        // panel rather than the limited inline-only variant, preserving the behavior
        // `EditItemSheet` used to opt into via `.writingToolsBehavior(.complete)` on the
        // old plain `TextEditor`. Guarded so a macOS 14 build simply doesn't set it,
        // exactly like the `TextEditor` version did with its own `#available` check.
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        controller.textView = textView
        controller.updateStats(from: textView.attributedString())
        controller.refreshActiveState()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only push the binding's value into the text view when it actually differs
        // from what the view already holds (e.g. a programmatic reset). Pushing on
        // every SwiftUI re-render would clobber the cursor position/selection with
        // every keystroke's own echo back through the binding.
        if textView.attributedString() != attributedText {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(selectedRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $attributedText, controller: controller)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<NSAttributedString>
        let controller: RichTextEditorController

        init(text: Binding<NSAttributedString>, controller: RichTextEditorController) {
            self.text = text
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let updated = textView.attributedString()
            text.wrappedValue = updated
            controller.updateStats(from: updated)
            controller.refreshActiveState()
        }

        /// Fires whenever the caret/selection moves (including as a side effect of
        /// typing), so the toolbar's active-state highlight tracks the cursor even when
        /// no toggle button was clicked.
        func textViewDidChangeSelection(_ notification: Notification) {
            controller.refreshActiveState()
        }
    }
}
