import SwiftUI

enum NavScreen: Hashable { case main, history, addAccount }

struct MenuContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var hoveredId: UUID? = nil
    @State private var appeared = false
    @State private var screen: NavScreen = .main
    @State private var historyTab: HistoryTab = .list

    enum HistoryTab { case list, chart, projects, sessions, heatmap, expensive }

    @AppStorage("emailsBlurred") private var emailsBlurred: Bool = false
    @AppStorage("isDarkMode")    private var isDarkMode: Bool = true
    @AppStorage("appLanguage")   private var appLanguage: String = "system"
    @Environment(\.colorScheme)  private var scheme

    /// Adaptive foreground: white in dark mode, black in light mode
    private var gw: Color { scheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: 0) {
            sideRail
            Divider().background(gw.opacity(0.06))

            VStack(spacing: 0) {
                navHeader
                switch screen {
                case .main:        mainContent
                case .history:     historyContent
                case .addAccount:  addAccountContent
                }
                Divider().background(gw.opacity(0.04))
                updateStatusStrip
            }
        }
        .background(.ultraThinMaterial)
        .background(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.15))
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appeared = true }
        }
        .onChange(of: isDarkMode) { _, _ in
            NotificationCenter.default.post(name: .appearanceChanged, object: nil)
        }
    }

    // MARK: - Nav Header

    private var navHeader: some View {
        Group {
            if screen != .main {
                HStack {
                    Text(screen == .history ? Str.history : Str.addAccount)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.72))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider().background(gw.opacity(0.06))
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if store.allExhausted && !store.profiles.isEmpty {
                exhaustionBanner
            }
            if store.profiles.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.profiles.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { separator }
                            profileRow(p)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var exhaustionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(Str.allExhausted)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.8))
                Spacer()
            }

            if let info = store.nextResetInfo {
                Text(L("İlk sıfırlanacak: \(info.profileName) — \(info.resetTime)",
                       "First reset: \(info.profileName) at \(info.resetTime)"))
                    .font(.system(size: 10))
                    .foregroundStyle(gw.opacity(0.45))
            }

            Button {
                store.switchToNext(reason: Str.manualOverride)
            } label: {
                Text(Str.switchAnyway)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(gw.opacity(0.6))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(gw.opacity(0.03))
    }

    // MARK: - History Content

    private var historyContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                iconTab("list.bullet",                   L("Geçmiş","History"),   historyTab == .list)      { historyTab = .list }
                tabDivider
                iconTab("chart.line.uptrend.xyaxis",     L("Grafik","Chart"),     historyTab == .chart)     { historyTab = .chart }
                tabDivider
                iconTab("folder.fill",                   L("Projeler","Projects"),historyTab == .projects)  { historyTab = .projects }
                tabDivider
                iconTab("bubble.left.and.bubble.right",  L("Oturumlar","Sess."),  historyTab == .sessions)  { historyTab = .sessions }
                tabDivider
                iconTab("square.grid.2x2",               L("Isı","Heatmap"),      historyTab == .heatmap)   { historyTab = .heatmap }
                tabDivider
                iconTab("flame.fill",                    L("Pahalı","Top $"),     historyTab == .expensive) { historyTab = .expensive }
            }
            .frame(height: 38)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 2)

            analyticsRangeBar

            switchReliabilitySummary
            automationConfidenceCard
            accountReliabilityStrip

            Divider().background(gw.opacity(0.06))

            Group {
                switch historyTab {
                case .list:
                    if store.switchHistory.isEmpty && store.switchTimeline.isEmpty {
                        Text(Str.noHistory)
                            .font(.system(size: 12))
                            .foregroundStyle(gw.opacity(0.35))
                            .padding(40)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                if !store.switchTimeline.isEmpty {
                                    sectionLabel(Str.automation)
                                    ForEach(Array(store.switchTimeline.reversed().prefix(12))) { event in
                                        timelineRow(event)
                                        Divider().background(gw.opacity(0.05))
                                    }
                                }

                                if !store.switchHistory.isEmpty {
                                    sectionLabel(Str.switches)
                                    ForEach(store.switchHistory.reversed()) { event in
                                        historyRow(event)
                                        Divider().background(gw.opacity(0.05))
                                    }
                                }
                            }
                        }
                    }
                case .chart:
                    ScrollView(.vertical, showsIndicators: false) {
                        UsageChartView().environmentObject(store)
                    }
                case .projects:
                    ProjectBreakdownView().environmentObject(store)
                case .sessions:
                    SessionExplorerView().environmentObject(store)
                case .heatmap:
                    ScrollView(.vertical, showsIndicators: false) {
                        HeatmapView().environmentObject(store)
                    }
                case .expensive:
                    ExpensivePromptsView().environmentObject(store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tabDivider: some View {
        Divider().frame(height: 18).background(gw.opacity(0.08))
    }

    private var analyticsRangeBar: some View {
        HStack(spacing: 8) {
            Text(Str.range)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(gw.opacity(0.28))

            ForEach(AnalyticsTimeRange.allCases, id: \.rawValue) { range in
                Button {
                    store.setAnalyticsTimeRange(range)
                } label: {
                    Text(range.title)
                        .font(.system(size: 9, weight: store.analyticsTimeRange == range ? .semibold : .regular))
                        .foregroundStyle(store.analyticsTimeRange == range ? gw.opacity(0.72) : gw.opacity(0.3))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(store.analyticsTimeRange == range ? gw.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var switchReliabilitySummary: some View {
        HStack(spacing: 10) {
            summaryPill(
                label: Str.queued,
                value: "\(store.switchReliability.pendingSwitchCount)",
                tint: .orange
            )
            summaryPill(
                label: Str.seamless,
                value: "\(store.switchReliability.seamlessSuccessCount)",
                tint: .green
            )
            summaryPill(
                label: Str.fallback,
                value: "\(store.switchReliability.fallbackRestartCount)",
                tint: .blue
            )

            Spacer(minLength: 0)

            if let lastResult = store.lastSeamlessSwitchResult {
                Text(switchOutcomeLabel(lastResult.outcome))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(switchOutcomeColor(lastResult.outcome).opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var automationConfidenceCard: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(automationConfidenceColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: automationConfidenceIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(automationConfidenceColor.opacity(0.82))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(Str.automationConfidence)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.72))
                    Text(automationConfidenceLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(automationConfidenceColor.opacity(0.82))
                }

                Text(store.automationConfidence.highlight)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.32))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    metricCapsule(label: Str.stale, value: "\(store.automationConfidence.staleProfileCount)")
                    metricCapsule(label: Str.fallback, value: "\(store.automationConfidence.fallbackRestartCount)")
                    metricCapsule(label: Str.seamless, value: "\(store.automationConfidence.seamlessSuccessCount)")
                    if let lastVerifiedSwitchAt = store.automationConfidence.lastVerifiedSwitchAt {
                        metricCapsule(label: Str.lastVerified, value: relativeShort(lastVerifiedSwitchAt))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var accountReliabilityStrip: some View {
        Group {
            if !store.accountReliability.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Str.accountsNeedingAttention)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(gw.opacity(0.28))
                            .textCase(.uppercase)
                        Spacer()
                    }

                    ForEach(Array(store.accountReliability.prefix(3))) { summary in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accountReliabilityColor(summary.status).opacity(0.85))
                                .frame(width: 6, height: 6)
                            Text(summary.profileName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(gw.opacity(0.68))
                                .lineLimit(1)
                            Text(summary.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(gw.opacity(0.28))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let riskLabel = summary.riskLabel {
                                Text(riskLabel)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(accountReliabilityColor(summary.status).opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func iconTab(_ icon: String, _ label: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 7, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 34)
            .foregroundStyle(selected ? gw.opacity(0.8) : gw.opacity(0.32))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func summaryPill(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(gw.opacity(0.28))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.8))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(gw.opacity(0.05))
        )
    }

    private func switchOutcomeLabel(_ outcome: SeamlessSwitchResult.Outcome) -> String {
        switch outcome {
        case .deferred: return Str.deferred
        case .seamlessSuccess: return L("Doğrulandı", "Verified")
        case .fallbackRestart: return Str.fallbackRestart
        case .inconclusive: return Str.inconclusive
        }
    }

    private func switchOutcomeColor(_ outcome: SeamlessSwitchResult.Outcome) -> Color {
        switch outcome {
        case .deferred: return .orange
        case .seamlessSuccess: return .green
        case .fallbackRestart: return .blue
        case .inconclusive: return gw
        }
    }

    private func tabBtn(icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? gw.opacity(0.75) : gw.opacity(0.35))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Add Account Content

    private var addAccountContent: some View {
        AddAccountInlineView().environmentObject(store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            codexAvatar(size: 44, active: false)
            Text(Str.noAccounts)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Separator

    private var separator: some View {
        Divider()
            .background(gw.opacity(0.06))
            .padding(.leading, 60)
    }

    private func healthDot(for profile: Profile) -> some View {
        let color: Color = {
            if store.staleProfileIds.contains(profile.id) { return .yellow }
            if store.rateLimits[profile.id] != nil { return .green }
            return .gray
        }()

        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    // MARK: - Profile Row

    private func profileRow(_ profile: Profile) -> some View {
        let isActive = profile.id == store.activeProfile?.id
        let rl = store.rateLimit(for: profile)
        let usage = store.getTokenUsage(for: profile)

        return Button {
            if !isActive { store.switchTo(profile: profile) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                profileAvatar(profile, size: 36, active: isActive)
                healthDot(for: profile)

                VStack(alignment: .leading, spacing: 3) {
                    // Name row
                    HStack(spacing: 5) {
                        Text(profile.displayName)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? gw : gw.opacity(0.6))
                            .lineLimit(1)

                        if isActive {
                            // Live indicator when session is active
                            if store.isSessionActive {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                    .shadow(color: .green, radius: 4)
                                    .opacity(0.8)
                            } else {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                    .opacity(0.5)
                            }
                        }

                        if let rl = store.rateLimit(for: profile), rl.limitReached {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.red.opacity(0.6))
                        }
                    }

                    // Email — blurrable
                    Text(profile.email)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(gw.opacity(0.4))
                        .lineLimit(1)
                        .blur(radius: emailsBlurred ? 5 : 0)
                        .animation(.easeInOut(duration: 0.2), value: emailsBlurred)

                    if let info = rl {
                        rateLimitRows(info: info)
                    } else if store.isFetchingLimits {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(height: 12)
                    }

                    if let health = store.rateLimitHealth[profile.id],
                       let healthLine = healthLine(for: health, profileId: profile.id) {
                        Text(healthLine)
                            .font(.system(size: 9))
                            .foregroundStyle(gw.opacity(0.25))
                            .lineLimit(1)
                    }

                    if let u = usage, u.totalTokens > 0 {
                        tokenUsageRow(u)
                    }

                    if let cost = store.costs[profile.id], cost > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(gw.opacity(0.3))
                            Text(CostCalculator.format(cost))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(gw.opacity(0.35))
                        }
                    }

                    if let forecast = store.forecasts[profile.id],
                       forecast.riskLevel != .safe && forecast.riskLevel != .exhausted {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(forecast.riskLevel.color))
                                .frame(width: 6, height: 6)
                            Text(forecast.riskLevel.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(gw.opacity(0.35))
                            if !forecast.timeToExhaustionLabel.isEmpty {
                                Text(forecast.timeToExhaustionLabel)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(gw.opacity(0.3))
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isActive ? "checkmark" : "chevron.right")
                    .font(.system(size: isActive ? 11 : 10, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? gw.opacity(0.45) : gw.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                isActive
                    ? gw.opacity(0.055)
                    : hoveredId == profile.id ? gw.opacity(0.035) : Color.clear
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { h in hoveredId = h ? profile.id : nil }
        .contextMenu {
            if store.staleProfileIds.contains(profile.id) {
                Button {
                    store.beginRelogin(for: profile)
                } label: {
                    Label(L("Girişi Yenile", "Re-login"), systemImage: "arrow.clockwise.circle")
                }
                Divider()
            }
            Button {
                store.showRenameDialog(for: profile)
            } label: {
                Label(Str.rename, systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                store.delete(profile: profile)
            } label: {
                Label(Str.delete, systemImage: "trash")
            }
        }
    }

    // MARK: - Rate Limit Rows

    @ViewBuilder
    private func rateLimitRows(info: RateLimitInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Haftalık: kalan % (Codex IDE formatı — yeşil bar, azaldıkça kötü)
            if let pct = info.weeklyRemainingPercent {
                limitRow(label: Str.weekly,
                         percent: pct,
                         resetLabel: info.weeklyResetLabel,
                         critical: pct <= 15,
                         isRemaining: true)
            }
            // 5 saatlik: kalan % (Codex IDE formatı)
            if info.isPlus, let pct = info.fiveHourRemainingPercent {
                limitRow(label: Str.fiveHour,
                         percent: pct,
                         resetLabel: info.fiveHourResetLabel,
                         critical: pct <= 15,
                         isRemaining: true)
            }
        }
    }

    private func limitRow(label: String, percent: Int, resetLabel: String, critical: Bool, isRemaining: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(gw.opacity(0.38))
                .frame(width: 40, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(gw.opacity(0.07))
                    Capsule()
                        .fill(critical
                              ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                              : LinearGradient(
                                  colors: isRemaining
                                      ? [Color.green.opacity(0.8), Color.green.opacity(0.5)]
                                      : [gw.opacity(0.6), gw.opacity(0.4)],
                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * Double(percent) / 100, percent > 0 ? 3 : 0))
                }
            }
            .frame(width: 60, height: 3)

            Text("\(percent)%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(critical ? .orange : gw.opacity(0.38))
                .frame(width: 26, alignment: .trailing)

            if !resetLabel.isEmpty {
                Text(resetLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))
            }
        }
    }

    // MARK: - Token Usage Row

    private func tokenUsageRow(_ u: AccountTokenUsage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 8))
                .foregroundStyle(gw.opacity(0.3))

            Text("\(formatTokens(u.totalTokens)) tokens")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(gw.opacity(0.32))

            // Most-used model
            if let topModel = u.modelUsage.max(by: { $0.value.totalTokens < $1.value.totalTokens })?.key {
                Text("· \(topModel)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.22))
            }

            if u.cachedInputTokens > 0 {
                Text("·")
                    .foregroundStyle(gw.opacity(0.2))
                Text("\(formatTokens(u.cachedInputTokens)) cached")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.22))
            }

            if u.sessionCount > 1 {
                Text("· \(u.sessionCount) sess")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.22))
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - History Row

    private func historyRow(_ event: SwitchEvent) -> some View {
        let isAuto = event.reason.contains("Limit") || event.reason.contains("doldu")
        let iconName = isAuto ? "bolt.fill" : "arrow.left.arrow.right"
        let iconColor: Color = isAuto ? .orange : .blue

        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let from = event.fromAccountName {
                        Text(from)
                            .font(.system(size: 11))
                            .foregroundStyle(gw.opacity(0.45))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(gw.opacity(0.3))
                    }
                    Text(event.toAccountName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(gw.opacity(0.8))
                }
                HStack(spacing: 6) {
                    Text(event.reason)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.3))
                    Text(event.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineRow(_ event: SwitchTimelineEvent) -> some View {
        let iconName: String = {
            switch event.stage {
            case .queued: return "pause.circle.fill"
            case .ready: return "checkmark.circle"
            case .verifying: return "ellipsis.circle"
            case .seamlessSuccess: return "bolt.horizontal.circle.fill"
            case .fallbackRestart: return "arrow.clockwise.circle.fill"
            case .inconclusive: return "questionmark.circle"
            }
        }()

        let tint: Color = {
            switch event.stage {
            case .queued: return .orange
            case .ready: return .yellow
            case .verifying: return .blue
            case .seamlessSuccess: return .green
            case .fallbackRestart: return .blue
            case .inconclusive: return gw
            }
        }()

        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(timelineStageLabel(event.stage))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.74))
                    Text(event.targetProfileName)
                        .font(.system(size: 10))
                        .foregroundStyle(gw.opacity(0.42))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(event.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.24))
                }

                Text(event.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let reason = event.reason, !reason.isEmpty {
                        metricCapsule(label: Str.reason, value: reason)
                    }
                    if let wait = event.waitDurationSeconds {
                        metricCapsule(label: Str.wait, value: "\(wait)s")
                    }
                    if let verification = event.verificationDurationSeconds {
                        metricCapsule(label: Str.verify, value: "\(verification)s")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(gw.opacity(0.28))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func metricCapsule(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(gw.opacity(0.22))
            Text(value)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(gw.opacity(0.42))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(gw.opacity(0.05))
        )
    }

    private var automationConfidenceColor: Color {
        switch store.automationConfidence.status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var automationConfidenceIcon: String {
        switch store.automationConfidence.status {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .critical: return "bolt.shield.fill"
        }
    }

    private var automationConfidenceLabel: String {
        switch store.automationConfidence.status {
        case .healthy: return Str.healthy
        case .warning: return Str.attention
        case .critical: return Str.critical
        }
    }

    private func accountReliabilityColor(_ status: AccountReliabilityStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func relativeShort(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func timelineStageLabel(_ stage: SwitchTimelineEvent.Stage) -> String {
        switch stage {
        case .queued: return L("Kuyrukta", "Queued")
        case .ready: return L("Hazır", "Ready")
        case .verifying: return L("Doğrulanıyor", "Verifying")
        case .seamlessSuccess: return Str.seamless
        case .fallbackRestart: return Str.fallbackRestart
        case .inconclusive: return Str.inconclusive
        }
    }

    // MARK: - Profile Avatar

    private func profileAvatar(_ profile: Profile, size: CGFloat, active: Bool) -> some View {
        codexAvatar(size: size, active: active)
    }

    // MARK: - Codex Avatar

    private func codexAvatar(size: CGFloat, active: Bool) -> some View {
        Group {
            if let img = loadCodexIcon() {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                    .opacity(active ? 1 : 0.42)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color(white: 0.12))
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                }
                .frame(width: size, height: size)
                .opacity(active ? 1 : 0.42)
            }
        }
    }

    private func loadCodexIcon() -> NSImage? {
        if let url = Bundle.appResources.url(forResource: "codex", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    // MARK: - Sidebar

    private var sideRail: some View {
        let langLabel: String = {
            switch appLanguage {
            case "tr": return "TR"
            case "en": return "EN"
            default:   return Str.langAuto
            }
        }()

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                railButton(
                    "rectangle.stack.person.crop",
                    L("Hesaplar", "Accounts"),
                    selected: screen == .main
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .main }
                }

                railDivider

                railButton(
                    "plus",
                    Str.addAccount,
                    selected: screen == .addAccount
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .addAccount }
                }
                .disabled(store.isAddingAccount)

                railDivider

                railButton(
                    "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    Str.history,
                    selected: screen == .history
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .history }
                }

                railDivider

                railButton("arrow.triangle.2.circlepath", Str.switchNow) {
                    store.switchToNext()
                }
                .disabled(store.profiles.count < 2)

                railDivider

                updateRailButton
            }
            .padding(.top, 6)

            Spacer(minLength: 10)

            VStack(spacing: 0) {
                railButton("globe", langLabel) {
                    if appLanguage == "system"   { appLanguage = "tr" }
                    else if appLanguage == "tr"  { appLanguage = "en" }
                    else                         { appLanguage = "system" }
                }

                railDivider

                railButton("eye", emailsBlurred ? Str.showEmail : Str.hideEmail) {
                    withAnimation(.easeInOut(duration: 0.2)) { emailsBlurred.toggle() }
                }

                railDivider

                railButton(isDarkMode ? "moon.fill" : "sun.max", isDarkMode ? Str.dark : Str.light) {
                    isDarkMode.toggle()
                }

                railDivider

                railButton("dollarsign.circle", budgetLabel) {
                    showBudgetAlert()
                }

                railDivider

                railButton("arrow.counterclockwise", L("Sıfırla", "Reset")) {
                    store.resetStatistics()
                }

                railDivider

                railButton("power", Str.quit) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(width: 68)
    }

    private var updateStatusStrip: some View {
        HStack(spacing: 8) {
            if let pending = store.pendingSwitchRequest {
                Text(L("Sırada", "Queued"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.78))

                Text(pending.targetProfileName)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.34))

                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.18))
            }

            if store.switchOrchestrationState == .verifying {
                Text(L("Doğrulanıyor", "Verifying"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.blue.opacity(0.72))

                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.18))
            }

            Text("v\(store.updateStatus.currentVersion)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(gw.opacity(0.42))

            Text("→")
                .font(.system(size: 9))
                .foregroundStyle(gw.opacity(0.18))

            Text(store.updateStatus.latestVersion.map { "v\($0)" } ?? "—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(gw.opacity(0.34))

            if let lastCheckedAt = store.updateStatus.lastCheckedAt {
                Text("· \(L("Son kontrol", "Checked")) \(compactTime(lastCheckedAt))")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.22))
            }

            Spacer()

            Text(updateStateLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(updateStateColor.opacity(0.72))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Budget

    private var budgetLabel: String {
        let limit = UserDefaults.standard.double(forKey: "weeklyBudgetUSD")
        if limit <= 0 { return L("Bütçe", "Budget") }
        let spent = store.costs.values.reduce(0, +)
        return "$\(String(format: "%.0f", spent))/$\(String(format: "%.0f", limit))"
    }

    private func showBudgetAlert() {
        let alert = NSAlert()
        alert.messageText = L("Haftalık bütçe limiti", "Weekly budget limit (USD)")
        alert.informativeText = L("0 girerek devre dışı bırakın.", "Enter 0 to disable.")
        alert.addButton(withTitle: L("Kaydet", "Save"))
        alert.addButton(withTitle: L("İptal", "Cancel"))

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let current = UserDefaults.standard.double(forKey: "weeklyBudgetUSD")
        tf.stringValue = current > 0 ? String(format: "%.2f", current) : ""
        tf.placeholderString = "0.00"
        tf.bezelStyle = .roundedBezel
        alert.accessoryView = tf

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let val = Double(tf.stringValue.replacingOccurrences(of: ",", with: ".")) ?? 0
            UserDefaults.standard.set(max(0, val), forKey: "weeklyBudgetUSD")
            store.refreshTokenUsage()
        }
    }

    // MARK: - Shared Helpers

    private var railDivider: some View {
        Divider()
            .background(gw.opacity(0.05))
            .padding(.horizontal, 14)
    }

    private var updateRailButton: some View {
        Button {
            if store.availableUpdate != nil {
                store.openReleasePage()
            } else {
                store.checkForUpdatesManually()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                railButtonBody(
                    icon: "arrow.down.circle",
                    label: L("Güncelle", "Update"),
                    selected: false,
                    foreground: store.availableUpdate != nil ? Color.orange.opacity(0.85) : gw.opacity(0.46)
                )

                if store.availableUpdate != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .offset(x: -20, y: 10)
                }
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func railButton(
        _ icon: String,
        _ label: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            railButtonBody(icon: icon, label: label, selected: selected, foreground: selected ? gw.opacity(0.76) : gw.opacity(0.42))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func railButtonBody(icon: String, label: String, selected: Bool, foreground: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))

            Text(label)
                .font(.system(size: 7, weight: selected ? .semibold : .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .foregroundStyle(foreground)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? gw.opacity(0.06) : .clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private var updateStateLabel: String {
        switch store.updateStatus.state {
        case .idle: return Str.idle
        case .checking: return Str.checking
        case .upToDate: return L("Güncel", "Up to date")
        case .updateAvailable: return Str.updateAvailableShort
        case .failed: return Str.failed
        }
    }

    private var updateStateColor: Color {
        switch store.updateStatus.state {
        case .idle: return gw.opacity(0.3)
        case .checking: return .blue
        case .upToDate: return .green
        case .updateAvailable: return .orange
        case .failed: return .red
        }
    }

    private func compactTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: date)
    }

    private func healthLine(for health: RateLimitHealthStatus, profileId: UUID) -> String? {
        if store.staleProfileIds.contains(profileId) {
            var parts: [String] = [Str.stale]
            if let reason = health.staleReason?.summary {
                parts.append(reason)
            }
            if let lastOk = health.lastSuccessfulFetchAt {
                parts.append("\(Str.lastOk) \(compactTime(lastOk))")
            }
            return parts.joined(separator: " · ")
        }

        if let failure = health.failureSummary {
            var parts: [String] = [failure]
            if let code = health.lastHTTPStatusCode {
                parts.append("HTTP \(code)")
            }
            if let lastOk = health.lastSuccessfulFetchAt {
                parts.append("\(Str.lastOk) \(compactTime(lastOk))")
            }
            return parts.joined(separator: " · ")
        }

        return nil
    }
}
