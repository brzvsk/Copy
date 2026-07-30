import AppKit
import ApplicationServices
import Combine
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Paged first-run flow, shown once by `AppCoordinator.showOnboarding()` and gated on
/// the `"hasOnboarded"` UserDefaults flag (set in `finish()`). Steps are computed once
/// at init rather than as a fixed `CaseIterable` list because the clipboard-access page
/// only makes sense on macOS versions where `NSPasteboard.accessBehavior` exists.
struct OnboardingView: View {
    private enum Step: Equatable {
        case welcome
        case accessibility
        case clipboardAccess
        case hotkey
        case done
    }

    let onFinish: () -> Void

    private let steps: [Step]
    @State private var stepIndex = 0

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        var steps: [Step] = [.welcome, .accessibility]
        if Self.supportsClipboardAccessPrivacy {
            steps.append(.clipboardAccess)
        }
        steps.append(contentsOf: [.hotkey, .done])
        self.steps = steps
    }

    /// `NSPasteboard.accessBehavior` is only declared `API_AVAILABLE(macos(15.4))`; on
    /// older systems the clipboard-access step would have nothing to explain or show,
    /// so it's dropped from `steps` entirely rather than shown in some degraded form.
    private static var supportsClipboardAccessPrivacy: Bool {
        if #available(macOS 15.4, *) {
            return true
        }
        return false
    }

    private var currentStep: Step { steps[stepIndex] }
    private var isFirstStep: Bool { stepIndex == 0 }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    private var continueTitle: String {
        if isLastStep { return "Finish" }
        if currentStep == .welcome { return "Get Started" }
        return "Continue"
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 16) {
                ProgressDots(count: steps.count, current: stepIndex)
                HStack {
                    if !isFirstStep {
                        Button("Back") {
                            withAnimation(.easeOut(duration: 0.15)) { stepIndex -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(continueTitle) { advance() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .welcome:
            WelcomeStep()
        case .accessibility:
            AccessibilityStep()
        case .clipboardAccess:
            ClipboardAccessStep()
        case .hotkey:
            HotkeyStep()
        case .done:
            DoneStep()
        }
    }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            withAnimation(.easeOut(duration: 0.15)) { stepIndex += 1 }
        }
    }

    /// The last step's Finish action: records that onboarding is done so it never shows
    /// again, best-effort enables Launch at Login (mirrors `GeneralSettings`'s toggle,
    /// but a failure here shouldn't block finishing onboarding), then hands off to the
    /// window controller's `onFinish` to actually hide the window.
    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        try? SMAppService.mainApp.register()
        onFinish()
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StepHeading: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Welcome to Copy")
                .font(.title2.weight(.semibold))
            Text("A visual shelf for everything you copy.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Press ⇧⌘V anytime to open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AccessibilityStep: View {
    @State private var isTrusted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            StepHeading(symbol: "accessibility", title: "Accessibility Access")
            Text("Copy pastes into the app you are using, which needs Accessibility access.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Accessibility Settings") { requestAccess() }
                .buttonStyle(.bordered)
            StatusRow(isGranted: isTrusted, grantedText: "Access granted", pendingText: "Not granted yet")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isTrusted = AXIsProcessTrusted() }
        .onReceive(timer) { _ in isTrusted = AXIsProcessTrusted() }
    }

    private func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ClipboardAccessStep: View {
    @State private var isGranted = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            StepHeading(symbol: "clipboard", title: "Clipboard Access")
            Text("On this version of macOS, allow Copy to read the clipboard so it can save your history.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") { openPrivacySettings() }
                .buttonStyle(.bordered)
            StatusRow(isGranted: isGranted, grantedText: "Access granted", pendingText: "Not granted yet")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshStatus() }
        .onReceive(timer) { _ in refreshStatus() }
    }

    /// `NSPasteboard.AccessBehavior` reports `.alwaysAllow` once the user has granted
    /// (or the system has never needed to ask); `.default`/`.ask`/`.alwaysDeny` all mean
    /// Copy's background pasteboard monitoring isn't reliably granted yet.
    private func refreshStatus() {
        if #available(macOS 15.4, *) {
            isGranted = NSPasteboard.general.accessBehavior == .alwaysAllow
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct StatusRow: View {
    let isGranted: Bool
    let grantedText: String
    let pendingText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)
            Text(isGranted ? grantedText : pendingText)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct HotkeyStep: View {
    var body: some View {
        VStack(spacing: 16) {
            StepHeading(symbol: "keyboard", title: "Hotkey")
            KeyboardShortcuts.Recorder("Open Copy:", name: .toggleShelf)
            Text("You can change this anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.green)
            Text("You are all set.")
                .font(.title2.weight(.semibold))
            Text("Copy lives in your menu bar, ready when you need it.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
