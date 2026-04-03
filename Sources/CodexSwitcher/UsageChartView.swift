import SwiftUI
import Charts

struct UsageChartView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    private var gw: Color { scheme == .dark ? .white : .black }

    // MARK: - Chart data

    struct ChartPoint: Identifiable {
        let id = UUID()
        let day: Date
        let tokens: Int
        let label: String   // account display name
    }

    /// Accounts that have at least one non-zero day in the window
    private var activeProfiles: [Profile] {
        store.profiles.filter { profile in
            store.dailyUsage[profile.id]?.contains { $0.tokens > 0 } == true
        }
    }

    private var chartPoints: [ChartPoint] {
        activeProfiles.flatMap { profile in
            (store.dailyUsage[profile.id] ?? []).map { day in
                ChartPoint(day: day.dayStart, tokens: day.tokens, label: profile.displayName)
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private var rangeTitle: String {
        switch store.analyticsTimeRange {
        case .sevenDays: return L("Son 7 gün — Token kullanımı", "Last 7 days — Token usage")
        case .thirtyDays: return L("Son 30 gün — Token kullanımı", "Last 30 days — Token usage")
        case .allTime: return L("Tüm zamanlar — Token kullanımı", "All time — Token usage")
        }
    }

    private var emptyTitle: String {
        switch store.analyticsTimeRange {
        case .sevenDays: return L("Son 7 günde kullanım verisi yok", "No usage data in the last 7 days")
        case .thirtyDays: return L("Son 30 günde kullanım verisi yok", "No usage data in the last 30 days")
        case .allTime: return L("Henüz kullanım verisi yok", "No usage data yet")
        }
    }

    // MARK: - Body

    var body: some View {
        if chartPoints.isEmpty {
            Text(emptyTitle)
                .font(.system(size: 12))
                .foregroundStyle(gw.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(rangeTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(gw.opacity(0.38))
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(by: .value("Account", point.label))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    AreaMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(by: .value("Account", point.label))
                    .opacity(0.08)

                    PointMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(by: .value("Account", point.label))
                    .symbolSize(18)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.system(size: 8))
                            .foregroundStyle(gw.opacity(0.35))
                        AxisGridLine().foregroundStyle(gw.opacity(0.04))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(formatTokens(v))
                                    .font(.system(size: 8))
                                    .foregroundStyle(gw.opacity(0.3))
                            }
                        }
                        AxisGridLine().foregroundStyle(gw.opacity(0.04))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ForEach(activeProfiles) { profile in
                            HStack(spacing: 4) {
                                Circle()
                                    .frame(width: 5, height: 5)
                                Text(profile.displayName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(gw.opacity(0.45))
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(height: 150)
                .padding(.horizontal, 14)

                // Per-account 7-day summary
                Divider().background(gw.opacity(0.05)).padding(.top, 10)

                ForEach(activeProfiles) { profile in
                    let days = store.dailyUsage[profile.id] ?? []
                    let total = days.reduce(0) { $0 + $1.tokens }
                    HStack(spacing: 6) {
                        Text(profile.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(gw.opacity(0.5))
                        Spacer()
                        Text(formatTokens(total))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(gw.opacity(0.4))
                        Text("tok")
                            .font(.system(size: 9))
                            .foregroundStyle(gw.opacity(0.25))
                        if store.analyticsTimeRange == .sevenDays,
                           let cost = store.costs[profile.id], cost > 0 {
                            Text("·")
                                .foregroundStyle(gw.opacity(0.2))
                            Text(CostCalculator.format(cost))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(gw.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    Divider().background(gw.opacity(0.04)).padding(.leading, 14)
                }
            }
        }
    }
}
