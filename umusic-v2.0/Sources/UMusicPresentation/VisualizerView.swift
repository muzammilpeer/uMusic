import SwiftUI
import UMusicCore

public enum VisualizerPolicy {
    public static func framesPerSecond(isPlaying: Bool, isVisible: Bool, sceneActive: Bool, reduceMotion: Bool, lowEnergyMode: Bool) -> Int {
        guard isPlaying, isVisible, sceneActive, !reduceMotion else { return 0 }
        return lowEnergyMode ? 4 : 15
    }
    public static func bars(position: Double, count: Int = 24) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let phase = position * 2.1 + Double(index) * 0.67
            return min(max(0.18 + abs(sin(phase)) * 0.72, 0.1), 0.9)
        }
    }
}

struct PlaybackVisualizer: View {
    let snapshot: PlaybackSnapshot
    let lowEnergyMode: Bool
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let fps = VisualizerPolicy.framesPerSecond(isPlaying: snapshot.phase == .playing, isVisible: isVisible, sceneActive: scenePhase == .active, reduceMotion: reduceMotion, lowEnergyMode: lowEnergyMode)
        Group {
            if fps > 0 {
                TimelineView(.periodic(from: .now, by: 1 / Double(fps))) { timeline in
                    bars(position: snapshot.positionSeconds + timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1))
                }
            } else {
                bars(position: snapshot.positionSeconds)
            }
        }
        .frame(height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Decorative music visualization")
        .accessibilityHidden(true)
    }

    private func bars(position: Double) -> some View {
        GeometryReader { proxy in
            let values = VisualizerPolicy.bars(position: position)
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule().fill(UMusicTheme.accent.gradient).frame(height: proxy.size.height * value)
                }
            }
        }
    }
}
