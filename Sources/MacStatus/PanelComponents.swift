import Charts
import SwiftUI

struct MetricBadge {
    let text: String
    let color: Color
}

struct MetricCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var caption: String?
    var badge: MetricBadge?
    /// Recent history, drawn in the header next to the value to keep the card short.
    var trend: Sparkline?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let caption {
                        Text(caption)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let badge {
                    Text(badge.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badge.color.opacity(0.15)))
                }
                Spacer(minLength: 8)
                if let trend {
                    trend.frame(width: 64)
                }
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .contain)
    }
}

struct Sparkline: View {
    struct Series: Identifiable {
        let id: String
        let points: [HistoryPoint]
        let color: Color
    }

    let series: [Series]
    let domain: ClosedRange<Double>

    var body: some View {
        let end = series.compactMap { $0.points.last?.time }.max() ?? Date()
        Chart {
            ForEach(series) { line in
                ForEach(line.points, id: \.time) { point in
                    if series.count == 1 {
                        AreaMark(
                            x: .value("时间", point.time),
                            yStart: .value("基线", domain.lowerBound),
                            yEnd: .value("数值", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [line.color.opacity(0.3), line.color.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    }
                    LineMark(
                        x: .value("时间", point.time),
                        y: .value("数值", point.value),
                        series: .value("序列", line.id)
                    )
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-MetricHistory.window)...end)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    /// Zero-based domain that grows with the data but never collapses below `minimum`.
    static func domain(for series: [[HistoryPoint]], minimum: Double) -> ClosedRange<Double> {
        let peak = series.flatMap { $0 }.map(\.value).max() ?? 0
        return 0...max(minimum, peak * 1.15)
    }
}

/// Horizontal bar of adjacent segments; fractions are of the whole bar.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id: String
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: geometry.size.width * min(max(segment.fraction, 0), 1))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

struct DetailItem: Identifiable {
    let label: String
    let value: String
    var color: Color?

    var id: String { label }
}

/// Two-column label/value grid.
struct DetailGrid: View {
    let items: [DetailItem]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { index in
                GridRow {
                    if index + 1 < items.count {
                        cell(items[index])
                        cell(items[index + 1])
                    } else {
                        // A trailing odd item spans both columns so long values (load average) are not truncated.
                        cell(items[index]).gridCellColumns(2)
                    }
                }
            }
        }
        .font(.system(size: 11))
    }

    private func cell(_ item: DetailItem) -> some View {
        HStack(spacing: 5) {
            if let color = item.color {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(item.label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(item.value).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A titled group of rows in a card with a note below, as in a grouped list; set apart from the card above
/// so the title reads as belonging to its rows.
struct ListSection<Rows: View, Footer: View>: View {
    let title: String
    @ViewBuilder let rows: Rows
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { rows }
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) { footer }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.top, 6)
    }
}

/// Separator between list rows, inset to the row text.
struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 10)
    }
}

/// A list row's text when there are no rows to show.
struct ListPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }
}
