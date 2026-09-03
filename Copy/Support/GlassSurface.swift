import SwiftUI
import AppKit

/// Single switch point for adopting Liquid Glass across the app: every M7 surface
/// (shelf, cards, popovers, HUD, paste stack, settings) should route its background
/// through `glassSurface` rather than reaching for `NSVisualEffectView` directly, so
/// the macOS-version gate and the Reduce Transparency fallback only need to be right
/// in one place.
///
/// - macOS 26+ with Reduce Transparency OFF: renders `View.glassEffect(_:in:)`
///   (Liquid Glass), verified against the installed macOS 26.5 SDK's
///   `SwiftUICore.swiftinterface` — `nonisolated public func glassEffect(_ glass:
///   Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`, gated
///   `@available(iOS 26.0, macOS 26.0, ...)`. Apple's docs (fetched from the live
///   `developer.apple.com` JSON API for this page) describe it as anchoring the glass
///   material to the view's full frame, same footprint as a `.background(...)` — so it
///   drops into this app's existing `.background(ShelfBackground())` call sites as a
///   direct replacement.
/// - macOS < 26, or Reduce Transparency ON (checked live, including on macOS 26 — see
///   `ReduceTransparencyObserver` below): falls back to the app's existing `.hudWindow`
///   `NSVisualEffectView` material, corner-masked the same way the surface would have
///   been under glass.
///
/// `GlassEffectContainer` (for morphing multiple glass shapes into one another) isn't
/// used here — this helper renders one glass shape per surface. A later task that
/// places several glass surfaces close together (e.g. multiple shelf controls) and
/// wants them to blend/morph should wrap that group in `GlassEffectContainer`
/// independently; it composes fine with `glassSurface` underneath.
extension View {
    /// All four corners rounded by the same radius — the common case for cards,
    /// popovers, the HUD, and the paste stack.
    func glassSurface(cornerRadius: CGFloat) -> some View {
        modifier(GlassSurfaceModifier(corners: .all(cornerRadius)))
    }

    /// Independent per-corner radii for surfaces that intentionally use an asymmetric
    /// shape. The floating shelf now uses the uniform overload above.
    func glassSurface(corners: GlassSurfaceCorners) -> some View {
        modifier(GlassSurfaceModifier(corners: corners))
    }
}

/// Per-corner radii, mirroring `UnevenRoundedRectangle`'s leading/trailing-based
/// parameters (RTL-safe) so the same value drives both the macOS 26 glass shape and
/// the pre-26 `NSVisualEffectView` fallback's `CACornerMask`.
struct GlassSurfaceCorners: Equatable {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var bottomTrailing: CGFloat = 0

    static func all(_ radius: CGFloat) -> Self {
        .init(topLeading: radius, topTrailing: radius, bottomLeading: radius, bottomTrailing: radius)
    }

    /// Only the top corners rounded.
    static func top(_ radius: CGFloat) -> Self {
        .init(topLeading: radius, topTrailing: radius)
    }

    /// `CALayer.maskedCorners` has no per-corner radius, only a shared `cornerRadius`
    /// plus a mask of which corners it applies to. Every call site in this app rounds
    /// its corners uniformly, so the largest requested radius is the one shared
    /// radius the fallback path needs.
    fileprivate var fallbackRadius: CGFloat {
        max(topLeading, topTrailing, bottomLeading, bottomTrailing)
    }

    fileprivate var maskedCorners: CACornerMask {
        var mask: CACornerMask = []
        if topLeading > 0 { mask.insert(.layerMinXMaxYCorner) }
        if topTrailing > 0 { mask.insert(.layerMaxXMaxYCorner) }
        if bottomLeading > 0 { mask.insert(.layerMinXMinYCorner) }
        if bottomTrailing > 0 { mask.insert(.layerMaxXMinYCorner) }
        return mask
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let corners: GlassSurfaceCorners
    @StateObject private var reduceTransparency = ReduceTransparencyObserver()

    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency.isReduced {
            content.glassEffect(.regular, in: glassShape)
        } else {
            content.background(VisualEffectMaterial(corners: corners))
        }
    }

    /// `UnevenRoundedRectangle`/`.rect(topLeadingRadius:...)` has shipped since
    /// macOS 13 (confirmed in the SDK interface), well below this app's 14.0 floor —
    /// only `glassEffect` itself is macOS-26-exclusive, so this shape needs no
    /// availability gate of its own.
    private var glassShape: UnevenRoundedRectangle {
        .rect(
            topLeadingRadius: corners.topLeading,
            bottomLeadingRadius: corners.bottomLeading,
            bottomTrailingRadius: corners.bottomTrailing,
            topTrailingRadius: corners.topTrailing
        )
    }
}

/// Watches `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` so
/// `glassSurface` flips to/from its solid fallback the instant Reduce Transparency is
/// toggled in System Settings, with no relaunch required.
@MainActor
private final class ReduceTransparencyObserver: ObservableObject {
    @Published private(set) var isReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` guarantees this runs on the main thread, but the observer
            // block's type is `@Sendable`, so the compiler can't statically see that as
            // main-actor isolation — `assumeIsolated` asserts what's already true here.
            MainActor.assumeIsolated {
                self?.isReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

/// The pre-26 (and Reduce-Transparency-on) fallback: the app's existing `.hudWindow`
/// material, corner-masked exactly like the bespoke `ShelfBackground` this replaces.
private struct VisualEffectMaterial: NSViewRepresentable {
    let corners: GlassSurfaceCorners

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = corners.fallbackRadius
        view.layer?.maskedCorners = corners.maskedCorners
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = corners.fallbackRadius
        nsView.layer?.maskedCorners = corners.maskedCorners
    }
}
