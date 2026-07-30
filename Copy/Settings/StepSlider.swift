import SwiftUI

/// A Telegram-style discrete slider: labeled stops along a track, tick dots at each stop, a
/// filled accent portion up to the thumb, and a white thumb that follows the cursor while
/// dragging and settles onto the nearest stop. Drives an `Int` index into the labels.
///
/// Everything is positioned inside one `GeometryReader` so the labels sit over the same
/// stop x-positions as the ticks; the two end labels are clamped inward a touch so they
/// never clip past the edges.
struct StepSlider: View {
    let labels: [String]
    @Binding var index: Int
    var accent: Color = Tokens.electricBlue

    private let thumbSize: CGFloat = 20
    private let trackHeight: CGFloat = 4
    private let tickSize: CGFloat = 5
    private let labelY: CGFloat = 8
    private let trackY: CGFloat = 34
    private let edgeLabelInset: CGFloat = 30

    /// Live thumb x while dragging; `nil` snaps the thumb to the current stop.
    @State private var dragX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let n = max(labels.count, 2)
            let inset = thumbSize / 2
            let usable = max(w - thumbSize, 1)
            let current = dragX ?? stopX(clampedIndex, inset: inset, usable: usable, n: n)

            ZStack(alignment: .topLeading) {
                labelsLayer(width: w, inset: inset, usable: usable, n: n)
                baseTrack(width: usable, center: w / 2)
                filledTrack(inset: inset, current: current)
                ticksLayer(current: current, inset: inset, usable: usable, n: n)
                thumb(at: current)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        let x = min(max(gestureValue.location.x, inset), w - inset)
                        dragX = x
                        let fraction = (x - inset) / usable
                        index = min(max(Int((fraction * CGFloat(n - 1)).rounded()), 0), n - 1)
                    }
                    .onEnded { _ in dragX = nil }
            )
        }
        .frame(height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(labels.indices.contains(clampedIndex) ? labels[clampedIndex] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(clampedIndex + 1, labels.count - 1)
            case .decrement: index = max(clampedIndex - 1, 0)
            default: break
            }
        }
    }

    private var clampedIndex: Int {
        min(max(index, 0), labels.count - 1)
    }

    private func stopX(_ i: Int, inset: CGFloat, usable: CGFloat, n: Int) -> CGFloat {
        inset + usable * CGFloat(i) / CGFloat(n - 1)
    }

    private func labelsLayer(width: CGFloat, inset: CGFloat, usable: CGFloat, n: Int) -> some View {
        ForEach(0..<n, id: \.self) { i in
            Text(labels[i])
                .font(.system(size: 11, weight: i == clampedIndex ? .semibold : .regular))
                .foregroundStyle(i == clampedIndex ? Color.primary : Color.secondary)
                .fixedSize()
                .position(
                    x: min(max(stopX(i, inset: inset, usable: usable, n: n), edgeLabelInset), width - edgeLabelInset),
                    y: labelY
                )
        }
    }

    private func baseTrack(width: CGFloat, center: CGFloat) -> some View {
        Capsule()
            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.7))
            .frame(width: width, height: trackHeight)
            .position(x: center, y: trackY)
    }

    private func filledTrack(inset: CGFloat, current: CGFloat) -> some View {
        let filled = max(current - inset, 0)
        return Capsule()
            .fill(accent)
            .frame(width: filled, height: trackHeight)
            .position(x: inset + filled / 2, y: trackY)
    }

    private func ticksLayer(current: CGFloat, inset: CGFloat, usable: CGFloat, n: Int) -> some View {
        ForEach(0..<n, id: \.self) { i in
            let x = stopX(i, inset: inset, usable: usable, n: n)
            Circle()
                .fill(x <= current + 0.5 ? accent : Color(nsColor: .tertiaryLabelColor))
                .frame(width: tickSize, height: tickSize)
                .position(x: x, y: trackY)
        }
    }

    private func thumb(at x: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumbSize, height: thumbSize)
            .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .position(x: x, y: trackY)
    }
}
