// Ports the #letters queue dial from web/index.html, plus the swipe-to-connect
// gesture the web version has no way to offer.
import SwiftUI

struct LetterWheel: View {
    var letters: [Character]
    var selected: [Int]
    var isDisabled: Bool
    var onSelect: (Int) -> Void
    var onTrace: (_ index: Int, _ allowBacktrack: Bool) -> Void
    /// Called when a traced (rather than tapped) word is lifted.
    var onSwipeComplete: () -> Void

    /// `.letters { width: 242px }`, and 224px below the 420px breakpoint —
    /// which is every phone this ships on.
    var diameter: CGFloat = 224

    /// `@GestureState` is the only per-drag store SwiftUI resets on a cancelled
    /// gesture as well as a clean lift, so the trail can never be stranded.
    @GestureState private var isTracing = false
    @State private var fingerLocation: CGPoint?
    @State private var lastLocation: CGPoint?

    /// How far the finger must travel before the gesture counts as a trace
    /// rather than a tap.
    private static let backtrackThreshold: CGFloat = 6
    private static let swipeThreshold: CGFloat = 12
    /// Step along the travelled segment, so a fast flick cannot jump a token.
    private static let sampleStep: CGFloat = 8

    /// `.letter { width: 48px }` sits outside the 420px breakpoint, so the
    /// tokens keep their size while the dial shrinks.
    private var letterSize: CGFloat { 48 }
    private var orbitRadius: CGFloat { diameter * 0.37 }
    private var hubRadius: CGFloat { diameter * (34 / 242) }

    var body: some View {
        ZStack {
            dial
            trail
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                LetterToken(
                    letter: letter,
                    isSelected: selected.contains(index),
                    size: letterSize)
                    // `button:disabled { opacity: .42 }` applies to the letter
                    // buttons, not to the dial they sit on.
                    .opacity(isDisabled ? 0.42 : 1)
                    .position(position(of: index))
                    .accessibilityLabel("Letter \(String(letter))")
                    .accessibilityAddTraits(selected.contains(index) ? [.isSelected, .isButton] : .isButton)
                    .accessibilityAction { onSelect(index) }
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(traceGesture, isEnabled: !isDisabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Available letters")
    }

    // MARK: - Chrome

    private var dial: some View {
        Circle()
            .fill(RadialGradient(
                colors: [Palette.lavender, Palette.paper],
                center: .center,
                startRadius: hubRadius,
                endRadius: diameter * 0.5))
            .overlay(Circle().fill(Palette.space).frame(width: hubRadius * 2, height: hubRadius * 2))
            .overlay(
                Text("LETTER\nQUEUE")
                    .font(Typography.mono(9, weight: .heavy))
                    .lineSpacing(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true))
            .overlay(Circle().strokeBorder(Palette.space, lineWidth: Metrics.border))
            .background(Circle().fill(Palette.uv).offset(x: 6, y: 7))
    }

    /// The line the finger draws between connected letters.
    private var trail: some View {
        Path { path in
            guard let first = selected.first else { return }
            path.move(to: position(of: first))
            for index in selected.dropFirst() { path.addLine(to: position(of: index)) }
            if isTracing, let fingerLocation { path.addLine(to: fingerLocation) }
        }
        .stroke(Palette.uv.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
    }

    // MARK: - Gesture

    private var traceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTracing) { _, state, _ in state = true }
            .onChanged { value in
                let travelled = hypot(value.translation.width, value.translation.height)
                // `translation == .zero` marks the touch-down sample, which is
                // also the only place a stale `lastLocation` could leak in.
                let previous = value.translation == .zero
                    ? value.location
                    : (lastLocation ?? value.location)
                for point in Self.samples(from: previous, to: value.location) {
                    guard let index = index(near: point) else { continue }
                    onTrace(index, travelled > Self.backtrackThreshold)
                }
                lastLocation = value.location
                fingerLocation = value.location
            }
            .onEnded { value in
                lastLocation = nil
                fingerLocation = nil
                // A tap holds the selection so the player can keep building and
                // press Submit; a traced word goes the moment the finger lifts.
                let travelled = hypot(value.translation.width, value.translation.height)
                if travelled > Self.swipeThreshold { onSwipeComplete() }
            }
    }

    /// Points along the segment the finger covered since the last sample. The
    /// hit circles do not tile the ring for an eight-letter queue, so testing
    /// only the sampled point lets a fast flick step straight over a token.
    private static func samples(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > sampleStep else { return [end] }
        let steps = min(Int(distance / sampleStep), 64)
        return (1...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * t,
                           y: start.y + (end.y - start.y) * t)
        }
    }

    private func index(near point: CGPoint) -> Int? {
        let slop = letterSize * 0.62
        var best: (index: Int, distance: CGFloat)?
        for index in letters.indices {
            let centre = position(of: index)
            let distance = hypot(point.x - centre.x, point.y - centre.y)
            guard distance <= slop else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// `(Math.PI * 2 * index / letters.length) - Math.PI / 2` — first letter on top.
    private func position(of index: Int) -> CGPoint {
        guard !letters.isEmpty else { return CGPoint(x: diameter / 2, y: diameter / 2) }
        let angle = (2 * Double.pi * Double(index) / Double(letters.count)) - .pi / 2
        return CGPoint(
            x: diameter / 2 + cos(angle) * orbitRadius,
            y: diameter / 2 + sin(angle) * orbitRadius)
    }
}

private struct LetterToken: View {
    var letter: Character
    var isSelected: Bool
    var size: CGFloat

    var body: some View {
        Text(String(letter).uppercased())
            .font(.system(size: size * 0.4, weight: .black))
            .foregroundStyle(Palette.space)
            .frame(width: size, height: size)
            .background(Circle().fill(isSelected ? Palette.lime : Palette.paper))
            .overlay(Circle().strokeBorder(Palette.space, lineWidth: Metrics.border))
            .background(Circle()
                .fill(isSelected ? Palette.uv : Palette.space)
                .offset(x: 3, y: 3))
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isSelected)
    }
}

/// `#guess` — the letters traced so far, tracked wide like the CSS.
struct GuessDisplay: View {
    var guess: String

    var body: some View {
        Text(guess.isEmpty ? " " : guess.uppercased())
            .font(Typography.display(22))
            .fontWeight(.black)
            .tracking(3)
            .foregroundStyle(Palette.space)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.12), value: guess)
            .accessibilityLabel(guess.isEmpty ? "No letters selected" : "Current word \(guess)")
            .accessibilityAddTraits(.updatesFrequently)
            .onChange(of: guess) { _, word in
                AccessibilityNotification.Announcement(word.isEmpty ? "Cleared" : word).post()
            }
    }
}
