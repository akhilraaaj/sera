import SwiftUI

/// Linear progress matching Ring / Grid / Gauge chrome:
/// viz → left-aligned % + caption → days elapsed / days left cards.
struct LinearProgressBarView: View {
    var progress: Double
    var caption: String? = nil
    var daysElapsed: Int
    var daysRemaining: Int
    var segmentCount: Int = 28

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedLinearBar(
                progress: clampedProgress,
                segmentCount: segmentCount
            )
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f%%", clampedProgress * 100))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                if let caption {
                    Text(caption)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProgressMetricCards(
                daysElapsed: daysElapsed,
                daysRemaining: daysRemaining
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(String(format: "%.0f percent", clampedProgress * 100)))
        .animation(.easeInOut(duration: 0.45), value: clampedProgress)
    }
}

// MARK: - Segmented bar (same language as gauge blocks / ring dots)

private struct SegmentedLinearBar: View, Animatable {
    var progress: Double
    var segmentCount: Int

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let count = max(segmentCount, 2)
        let filled = Int((min(1, max(0, progress)) * Double(count)).rounded())
        let gap = size.width * 0.012
        let totalGaps = gap * CGFloat(count - 1)
        let blockWidth = (size.width - totalGaps) / CGFloat(count)
        let corner = min(blockWidth, size.height) * 0.28

        for index in 0..<count {
            let x = CGFloat(index) * (blockWidth + gap)
            let rect = CGRect(x: x, y: 0, width: blockWidth, height: size.height)
            let path = Path(roundedRect: rect, cornerRadius: corner)
            let active = index < filled
            context.fill(
                path,
                with: .color(active ? SeraTheme.progress : SeraTheme.track)
            )
        }
    }
}
