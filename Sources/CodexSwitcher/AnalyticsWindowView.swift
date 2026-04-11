import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct AnalyticsWindowView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    private var gw: Color { scheme == .dark ? .white : .black }
    private var snapshot: AnalyticsSnapshot { store.analyticsSnapshot }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let message = snapshot.dataQuality.message {
                    confidenceBanner(message: message, confidence: snapshot.dataQuality.confidence)
                }
                summaryBand
                trendSection
                breakdownSection
                limitPressureSection
                reconciliationSection
                diagnosticsSection
                alertsSection
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [
                    scheme == .dark ? Color.black.opacity(0.92) : Color.white.opacity(0.94),
                    scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.13) : Color(red: 0.93, green: 0.95, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .frame(minWidth: 920, minHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Analitik", "Analytics"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(gw.opacity(0.92))
                Text(L("Maliyet kontrolü ve operasyon görünürlüğü", "Cost control and operational visibility"))
                    .font(.system(size: 13))
                    .foregroundStyle(gw.opacity(0.46))

                HStack(spacing: 10) {
                    Text(L("Son başarılı fetch:", "Last successful fetch:"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(gw.opacity(0.34))
                    if let lastSuccessfulFetch = snapshot.dataQuality.lastSuccessfulFetch {
                        Text(lastSuccessfulFetch.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(gw.opacity(0.62))
                    } else {
                            Text(L("Henüz yok", "Not available yet"))
                            .font(.system(size: 11))
                            .foregroundStyle(gw.opacity(0.3))
                    }
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 10) {
                Picker(Str.range, selection: Binding(
                    get: { store.analyticsTimeRange },
                    set: { store.setAnalyticsTimeRange($0) }
                )) {
                    ForEach(AnalyticsTimeRange.allCases, id: \.rawValue) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Button {
                    store.refreshTokenUsage()
                } label: {
                    Label(L("Yenile", "Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(gw.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(gw.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func confidenceBanner(message: String, confidence: AnalyticsDataConfidence) -> some View {
        HStack(spacing: 10) {
            Image(systemName: confidence == .low ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(confidence == .low ? .orange : .yellow)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(gw.opacity(0.72))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(gw.opacity(0.06))
        )
    }

    private var summaryBand: some View {
        let cards: [(String, String, String)] = [
            (L("Toplam token", "Total tokens"), formatTokens(snapshot.summary.totalTokens), "chart.bar.fill"),
            (L("Tahmini maliyet", "Estimated cost"), CostCalculator.format(snapshot.summary.estimatedTotalCost), "dollarsign.circle.fill"),
            (
                L("En yoğun hesap", "Busiest account"),
                snapshot.summary.busiestAccountName ?? "—",
                snapshot.summary.busiestAccountTokens > 0 ? formatTokens(snapshot.summary.busiestAccountTokens) : "—"
            ),
            (
                L("En pahalı proje", "Most expensive project"),
                snapshot.summary.mostExpensiveProjectName ?? "—",
                snapshot.summary.mostExpensiveProjectCost > 0 ? CostCalculator.format(snapshot.summary.mostExpensiveProjectCost) : "—"
            ),
            (L("Aktif uyarı", "Active alerts"), "\(snapshot.summary.activeAlertCount)", "bell.badge.fill")
        ]

        return HStack(spacing: 12) {
            summaryCard(title: cards[0].0, primary: cards[0].1, secondary: L("Range toplamı", "Range total"), icon: cards[0].2)
            summaryCard(title: cards[1].0, primary: cards[1].1, secondary: L("Tahmini USD", "Estimated USD"), icon: cards[1].2)
            summaryCard(title: cards[2].0, primary: cards[2].1, secondary: cards[2].2, icon: "person.crop.circle.fill")
            summaryCard(title: cards[3].0, primary: cards[3].1, secondary: cards[3].2, icon: "folder.fill.badge.minus")
            summaryCard(title: cards[4].0, primary: cards[4].1, secondary: alertConfidenceLabel, icon: cards[4].2)
        }
    }

    private func summaryCard(title: String, primary: String, secondary: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(gw.opacity(0.58))
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(gw.opacity(0.34))
            }
            Text(primary)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(gw.opacity(0.9))
                .lineLimit(1)
            Text(secondary)
                .font(.system(size: 11))
                .foregroundStyle(gw.opacity(0.38))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var trendSection: some View {
        HStack(alignment: .top, spacing: 16) {
            trendCard(
                title: L("Token trendi", "Token trend"),
                points: snapshot.tokenTrend,
                value: \.tokens,
                formatter: formatTokens(_:),
                tint: .cyan
            )
            trendCard(
                title: L("Maliyet trendi", "Cost trend"),
                points: snapshot.costTrend,
                value: \.cost,
                formatter: CostCalculator.format(_:),
                tint: .orange
            )
        }
    }

    private func trendCard<Value: Plottable>(
        title: String,
        points: [AnalyticsTrendPoint],
        value: KeyPath<AnalyticsTrendPoint, Value>,
        formatter: @escaping (Value) -> String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, subtitle: bucketSubtitle)

            if points.isEmpty {
                emptyCardLabel
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.start),
                        y: .value("Value", point[keyPath: value])
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("Time", point.start),
                        y: .value("Value", point[keyPath: value])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.2), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: store.analyticsTimeRange == .twentyFourHours ? 6 : 5)) { value in
                        AxisGridLine().foregroundStyle(gw.opacity(0.05))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(gw.opacity(0.36))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(gw.opacity(0.05))
                        AxisValueLabel {
                            if let numeric = value.as(Value.self) {
                                Text(formatter(numeric))
                                    .font(.system(size: 9))
                                    .foregroundStyle(gw.opacity(0.34))
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Ana dashboard", "Main dashboard"),
                subtitle: L("Hesap, proje ve model dağılımları", "Account, project, and model breakdowns")
            )

            HStack(alignment: .top, spacing: 16) {
                breakdownCard(title: L("Hesap breakdown", "Account breakdown"), items: snapshot.accountBreakdown)
                breakdownCard(title: L("Proje breakdown", "Project breakdown"), items: snapshot.projectBreakdown)
                breakdownCard(title: L("Model breakdown", "Model breakdown"), items: snapshot.modelBreakdown)
            }
        }
    }

    private func breakdownCard(title: String, items: [AnalyticsBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gw.opacity(0.76))

            if items.isEmpty {
                emptyCardLabel
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(items.prefix(5))) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(gw.opacity(0.8))
                                    .lineLimit(1)
                                Spacer()
                                Text(CostCalculator.format(item.cost))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(gw.opacity(0.42))
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(gw.opacity(0.05))
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.cyan.opacity(0.75), .blue.opacity(0.55)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(4, geo.size.width * max(item.shareOfCost, item.shareOfTokens)))
                                }
                            }
                            .frame(height: 5)

                            HStack(spacing: 8) {
                                Text(formatTokens(item.tokens))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(gw.opacity(0.34))
                                Text("·")
                                    .foregroundStyle(gw.opacity(0.18))
                                Text("\(Int((item.shareOfCost * 100).rounded()))%")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(gw.opacity(0.34))
                                Spacer()
                                Text(L("\(item.sessionCount) oturum", "\(item.sessionCount) sessions"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(gw.opacity(0.28))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var limitPressureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: L("Limit baskısı görünümü", "Limit pressure"),
                subtitle: L("Hesap bazlı risk ve fetch sağlığı", "Per-account risk and fetch health")
            )

            VStack(spacing: 10) {
                ForEach(snapshot.limitPressure) { pressure in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(riskColor(pressure.riskLevel).opacity(0.85))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pressure.profileName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(gw.opacity(0.82))
                                Text(pressure.riskLevel.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(riskColor(pressure.riskLevel).opacity(0.86))
                                Spacer()
                                Text(confidenceText(pressure.confidence))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(gw.opacity(0.34))
                            }

                            HStack(spacing: 10) {
                                pressureMetric(
                                    label: L("Haftalık", "Weekly"),
                                    value: pressure.weeklyRemainingPercent.map { "\($0)%" } ?? "—"
                                )
                                pressureMetric(
                                    label: L("5 saat", "5 hours"),
                                    value: pressure.fiveHourRemainingPercent.map { "\($0)%" } ?? "—"
                                )
                                pressureMetric(
                                    label: L("ETA", "ETA"),
                                    value: pressure.estimatedTimeToExhaustion?.formatted(date: .omitted, time: .shortened) ?? "—"
                                )
                            }

                            if let failureSummary = pressure.failureSummary ?? pressure.staleReason?.summary {
                                Text(failureSummary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(gw.opacity(0.34))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
                }
            }
        }
    }

    private var reconciliationSection: some View {
        AnalyticsReconciliationSection(
            snapshot: snapshot,
            foregroundColor: gw,
            exportAction: exportAudit(type:content:)
        )
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: L("Uyarılar", "Alerts"),
                subtitle: L("Ölçülebilir eşik ve trend sinyalleri", "Measured threshold and trend signals")
            )

            if snapshot.alerts.isEmpty {
                emptyCardLabel
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshot.alerts) { alert in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: alert.severity == .critical ? "exclamationmark.octagon.fill" : "bell.badge.fill")
                                .foregroundStyle(alert.severity == .critical ? .red : .orange)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(alert.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(gw.opacity(0.82))
                                    Spacer()
                                    Text(alert.severity.rawValue.capitalized)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(alert.severity == .critical ? .red.opacity(0.85) : .orange.opacity(0.85))
                                }
                                Text(alert.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(gw.opacity(0.48))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: L("Diagnostics", "Diagnostics"),
                subtitle: L("Birleşik operasyon zaman çizelgesi", "Unified operational timeline")
            )

            if snapshot.diagnosticsTimeline.isEmpty {
                emptyCardLabel
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        summaryMiniPill(label: L("Toplam", "Total"), value: "\(snapshot.diagnosticsSummary.totalCount)", tint: .blue)
                        summaryMiniPill(label: L("Warning", "Warning"), value: "\(snapshot.diagnosticsSummary.warningCount)", tint: .orange)
                        summaryMiniPill(label: L("Critical", "Critical"), value: "\(snapshot.diagnosticsSummary.criticalCount)", tint: .red)
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    ForEach(snapshot.diagnosticsTimeline.prefix(12)) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(diagnosticsColor(event.severity).opacity(0.9))
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(gw.opacity(0.82))
                                    if let subject = event.subject, !subject.isEmpty {
                                        Text(subject)
                                            .font(.system(size: 10))
                                            .foregroundStyle(gw.opacity(0.38))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(event.timestamp, style: .relative)
                                        .font(.system(size: 10))
                                        .foregroundStyle(gw.opacity(0.3))
                                }
                                HStack(spacing: 8) {
                                    diagnosticCapsule(event.kind.rawValue)
                                    diagnosticCapsule(event.severity.rawValue)
                                }
                                Text(event.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(gw.opacity(0.48))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(gw.opacity(0.84))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(gw.opacity(0.34))
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(gw.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(gw.opacity(0.05), lineWidth: 1)
            )
    }

    private var emptyCardLabel: some View {
        Text(L("Bu aralık için veri yok", "No data for this range"))
            .font(.system(size: 12))
            .foregroundStyle(gw.opacity(0.32))
    }

    private var bucketSubtitle: String {
        switch store.analyticsTimeRange {
        case .twentyFourHours:
            return L("Saatlik bucket", "Hourly buckets")
        case .sevenDays, .thirtyDays, .allTime:
            return L("Günlük bucket", "Daily buckets")
        }
    }

    private var alertConfidenceLabel: String {
        switch snapshot.dataQuality.confidence {
        case .high: return L("Veri taze", "Fresh data")
        case .degraded: return L("Veri yaşlanıyor", "Aging data")
        case .low: return L("Veri sorunlu", "Data issues")
        }
    }

    private func axisLabel(for date: Date) -> String {
        if store.analyticsTimeRange == .twentyFourHours {
            return date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func riskColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .safe: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .critical, .exhausted: return .red
        }
    }

    private func confidenceText(_ confidence: AnalyticsDataConfidence) -> String {
        switch confidence {
        case .high: return L("Veri taze", "Fresh data")
        case .degraded: return L("Veri yaşlanıyor", "Aging data")
        case .low: return L("Veri sorunlu", "Data issues")
        }
    }

    private func pressureMetric(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(gw.opacity(0.28))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(gw.opacity(0.56))
        }
    }

    private func diagnosticsColor(_ severity: DiagnosticsEventSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func summaryMiniPill(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(gw.opacity(0.34))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(gw.opacity(0.06)))
    }

    private func diagnosticCapsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(gw.opacity(0.4))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(gw.opacity(0.05)))
    }

    private func exportButton(title: String, type: UTType, content: @escaping () throws -> String) -> some View {
        Button {
            exportAudit(type: type, content: content)
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(gw.opacity(0.52))
        }
        .buttonStyle(.plain)
    }

    private func exportAudit(type: UTType, content: @escaping () throws -> String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = type == .json ? "codex-audit.json" : "codex-audit.csv"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let output = try content()
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
        }
    }

}
