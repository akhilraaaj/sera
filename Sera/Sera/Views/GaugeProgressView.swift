import SwiftUI

/// Semicircle gauge matching the reference layout, in Sera monochrome.
struct GaugeProgressView: View {
    var progress: Double
    var caption: String
    var daysElapsed: Int
    var daysRemaining: Int
    var weeksRemaining: Int = 0
    var segmentCount: Int = 15

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        VStack(spacing: 14) {
            gaugeHeader

            ProgressMetricCards(
                daysElapsed: daysElapsed,
                daysRemaining: daysRemaining
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress gauge")
        .accessibilityValue(Text(String(format: "%.1f percent", clamped * 100)))
        .animation(.easeInOut(duration: 0.4), value: clamped)
    }

    private var gaugeHeader: some View {
        ZStack {
            SegmentedSemicircleGauge(
                progress: clamped,
                segmentCount: segmentCount
            )
            .frame(maxWidth: .infinity)
            .frame(height: 168)

            VStack(spacing: 2) {
                Text(String(format: "%.1f%%", clamped * 100))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(caption)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .offset(y: 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

}

/// Shared “Days elapsed / Days left” cards for gauge, ring, and grid.
struct ProgressMetricCards: View {
    var daysElapsed: Int
    var daysRemaining: Int

    var body: some View {
        HStack(spacing: 10) {
            metricCard(title: "Days elapsed", value: formatted(daysElapsed))
            metricCard(title: "Days left", value: formatted(daysRemaining))
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

// MARK: - Radial block semicircle (matches reference)

struct SegmentedSemicircleGauge: View {
    var progress: Double
    var segmentCount: Int

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let count = max(segmentCount, 2)
        let filled = Int((min(1, max(0, progress)) * Double(count)).rounded())

        // Fill nearly the full width; tiny margin keeps end blocks whole.
        let margin: CGFloat = 5
        let blockLength = size.width * 0.078
        let maxOuterRadius = size.width * 0.5 - margin
        let radius = maxOuterRadius - blockLength * 0.5
        guard radius > 24 else { return }

        let topInset = blockLength * 0.55
        let center = CGPoint(x: size.width * 0.5, y: topInset + radius)

        let startAngle = Double.pi
        let endAngle = 0.0
        let span = startAngle - endAngle
        let slotWidth = CGFloat(span / Double(count)) * radius
        let blockWidth = slotWidth * 0.90
        let corner = blockWidth * 0.36

        for index in 0..<count {
            let t = (Double(index) + 0.5) / Double(count)
            let angle = startAngle - t * span

            let mid = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y - CGFloat(sin(angle)) * radius
            )

            let rotation = Double.pi / 2 - angle
            let active = index < filled

            let rect = CGRect(
                x: -blockWidth * 0.5,
                y: -blockLength * 0.5,
                width: blockWidth,
                height: blockLength
            )
            let path = Path(roundedRect: rect, cornerRadius: corner)

            context.drawLayer { layer in
                layer.translateBy(x: mid.x, y: mid.y)
                layer.rotate(by: .radians(rotation))
                layer.fill(
                    path,
                    with: .color(active ? SeraTheme.progress : SeraTheme.track)
                )
            }
        }
    }
}
