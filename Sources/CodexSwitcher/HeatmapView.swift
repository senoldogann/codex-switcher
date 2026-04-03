import SwiftUI

struct HeatmapView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    private var gw: Color { scheme == .dark ? .white : .black }

    private let days   = ["M", "T", "W", "T", "F", "S", "S"]
    private let cellW: CGFloat = 11
    private let cellH: CGFloat = 11
    private let gap:   CGFloat = 2

    private var maxTokens: Int {
        store.hourlyActivity.map(\.tokens).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hour axis labels (0, 4, 8 … 20)
            HStack(spacing: 0) {
                Spacer().frame(width: 18) // left label column
                ForEach(0..<24, id: \.self) { hour in
                    if hour % 4 == 0 {
                        Text("\(hour)")
                            .font(.system(size: 7))
                            .foregroundStyle(gw.opacity(0.3))
                            .frame(width: (cellW + gap) * 4, alignment: .leading)
                    }
                }
            }

            // Grid: 7 rows (Mon–Sun) × 24 cols (hours)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<7, id: \.self) { dow in
                    HStack(spacing: gap) {
                        // Day label
                        Text(days[dow])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(gw.opacity(0.3))
                            .frame(width: 14, alignment: .trailing)

                        ForEach(0..<24, id: \.self) { hour in
                            let tokens = tokensFor(dow: dow, hour: hour)
                            cell(tokens: tokens)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Text(L("Az", "Less"))
                    .font(.system(size: 8))
                    .foregroundStyle(gw.opacity(0.3))
                ForEach([0, 0.25, 0.5, 0.75, 1.0], id: \.self) { frac in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(fraction: frac))
                        .frame(width: cellW, height: cellH)
                }
                Text(L("Çok", "More"))
                    .font(.system(size: 8))
                    .foregroundStyle(gw.opacity(0.3))
            }
            .padding(.leading, 18)

            // Peak hours summary
            peakSummary
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(tokens: Int) -> some View {
        let fraction = maxTokens > 0 ? Double(tokens) / Double(maxTokens) : 0
        return RoundedRectangle(cornerRadius: 2)
            .fill(cellColor(fraction: fraction))
            .frame(width: cellW, height: cellH)
    }

    private func cellColor(fraction: Double) -> Color {
        if fraction == 0 { return gw.opacity(0.06) }
        if fraction < 0.33 {
            return Color.blue.opacity(0.25 + fraction * 0.6)
        } else if fraction < 0.66 {
            return Color.blue.opacity(0.45).mix(with: .orange.opacity(0.6), by: fraction)
        } else {
            return Color.orange.opacity(0.6 + fraction * 0.3)
        }
    }

    private func tokensFor(dow: Int, hour: Int) -> Int {
        store.hourlyActivity.first { $0.dayOfWeek == dow && $0.hour == hour }?.tokens ?? 0
    }

    // Summary: peak day + peak hour
    @ViewBuilder
    private var peakSummary: some View {
        let byDay  = (0..<7).map  { dow  in (dow,  store.hourlyActivity.filter { $0.dayOfWeek == dow  }.map(\.tokens).reduce(0, +)) }
        let byHour = (0..<24).map { hour in (hour, store.hourlyActivity.filter { $0.hour == hour       }.map(\.tokens).reduce(0, +)) }

        if let peakDay  = byDay.max(by:  { $0.1 < $1.1 }),
           let peakHour = byHour.max(by: { $0.1 < $1.1 }),
           peakDay.1 > 0 {
            let dayNames = [L("Pazartesi","Monday"), L("Salı","Tuesday"), L("Çarşamba","Wednesday"),
                            L("Perşembe","Thursday"), L("Cuma","Friday"), L("Cumartesi","Saturday"),
                            L("Pazar","Sunday")]
            HStack(spacing: 12) {
                Label(dayNames[peakDay.0], systemImage: "calendar")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.4))
                Label("\(peakHour.0):00", systemImage: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.4))
                Text(L("en yoğun", "peak"))
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.25))
            }
            .padding(.leading, 18)
        }
    }
}

private extension Color {
    func mix(with other: Color, by fraction: Double) -> Color {
        // Simple interpolation via opacity layering
        return self.opacity(1 - fraction).blended(withFraction: fraction, of: other)
    }
    func blended(withFraction f: Double, of other: Color) -> Color {
        // Fallback: just use the other color at increasing opacity
        return other.opacity(f)
    }
}
