import SwiftUI

struct ExpensivePromptsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    private var gw: Color { scheme == .dark ? .white : .black }

    private var metrics: ExpensiveTurnMetrics {
        ExpensiveTurnMetrics(turns: store.expensiveTurns)
    }

    var body: some View {
        if store.expensiveTurns.isEmpty {
            Text(L("Veri yok", "No data yet"))
                .font(.system(size: 12))
                .foregroundStyle(gw.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.expensiveTurns.enumerated()), id: \.element.id) { rank, turn in
                        turnRow(turn, rank: rank + 1)
                        Divider().background(gw.opacity(0.05))
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func turnRow(_ turn: ExpensiveTurn, rank: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Rank number
            Text("#\(rank)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(rankColor(rank).opacity(0.7))
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(turn.projectName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(gw.opacity(0.08))
                        .clipShape(Capsule())

                    Text(turn.model)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(gw.opacity(0.25))

                    Text(ExpensiveTurnMetrics.formatCost(turn.cost))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(rankColor(rank).opacity(0.85))

                    Spacer(minLength: 0)

                    Text(turn.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.22))
                }

                if !turn.promptPreview.isEmpty {
                    Text(turn.promptPreview)
                        .font(.system(size: 10))
                        .foregroundStyle(gw.opacity(0.65))
                        .lineLimit(2)
                }

                // Token bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(gw.opacity(0.06))
                        Capsule()
                            .fill(rankColor(rank).opacity(0.55))
                            .frame(width: max(4, geo.size.width * CGFloat(metrics.costFraction(for: turn))))
                    }
                }
                .frame(height: 3)

                Text(ExpensiveTurnMetrics.formatTokens(turn.tokens) + " tok")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(rankColor(rank).opacity(0.65))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1:  return .orange
        case 2:  return .yellow
        case 3:  return Color(red: 0.8, green: 0.6, blue: 0.3) // bronze
        default: return .blue
        }
    }
}
