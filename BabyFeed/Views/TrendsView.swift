import Charts
import SwiftUI

/// Two weeks of patterns: volume per day, feeds per day, and when feeds happen.
struct TrendsView: View {
    let groups: [DayGroup]
    let unit: VolumeUnit
    let targetML: Double?

    private var recentGroups: [DayGroup] { Array(groups.prefix(14)).reversed() }
    private var recentEntries: [FeedEntry] { recentGroups.flatMap(\.entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            chartBlock("Bottle volume per day") {
                Chart {
                    ForEach(recentGroups) { group in
                        BarMark(
                            x: .value("Day", group.day, unit: .day),
                            y: .value("Volume", unit.fromMilliliters(group.summary.totalML))
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                    }
                    if let targetML {
                        RuleMark(y: .value("Target", unit.fromMilliliters(targetML)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("target")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartYAxisLabel(unit.symbol)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: recentGroups.count > 7 ? 2 : 1)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 170)
            }

            chartBlock("Feeds per day") {
                Chart(recentGroups) { group in
                    BarMark(
                        x: .value("Day", group.day, unit: .day),
                        y: .value("Feeds", group.entries.count)
                    )
                    .foregroundStyle(Color.pink.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: recentGroups.count > 7 ? 2 : 1)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 140)
            }

            chartBlock("When feeds happen") {
                Chart(recentEntries) { entry in
                    PointMark(
                        x: .value("Hour", hourOfDay(entry.startTime)),
                        y: .value("Day", entry.startTime, unit: .day)
                    )
                    .foregroundStyle(entry.kind.color)
                    .symbolSize(60)
                }
                .chartXScale(domain: 0.0...24.0)
                .chartXAxis {
                    AxisMarks(values: [0.0, 6.0, 12.0, 18.0, 24.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hour = value.as(Double.self) {
                                Text(hourLabel(hour))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: CGFloat(max(recentGroups.count, 3)) * 24 + 40)

                HStack(spacing: 14) {
                    ForEach(FeedKind.allCases) { kind in
                        Label(kind.title, systemImage: "circle.fill")
                            .foregroundStyle(kind.color)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func chartBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func hourOfDay(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    private func hourLabel(_ hour: Double) -> String {
        switch Int(hour) {
        case 0, 24: "12a"
        case 12: "12p"
        case let h where h > 12: "\(h - 12)p"
        default: "\(Int(hour))a"
        }
    }
}
