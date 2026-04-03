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
        VStack(spacing: 0) {
            navHeader
            switch screen {
            case .main:        mainContent
            case .history:     historyContent
            case .addAccount:  addAccountContent
            }
            if screen == .main { footerBar }
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { screen = .main }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(Str.back)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(gw.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
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
        .frame(minHeight: 300)
        .frame(maxHeight: store.allExhausted ? 360 : 420)
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
                store.switchToNext(reason: L("Manuel override", "Manual override"))
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
            // Tab bar — 6 tabs, icon only to fit
            ScrollView(.horizontal, showsIndicators: false) {
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
            }
            .frame(height: 36)
            .padding(.horizontal, 14)

            Divider().background(gw.opacity(0.06))

            Group {
                switch historyTab {
                case .list:
                    if store.switchHistory.isEmpty {
                        Text(Str.noHistory)
                            .font(.system(size: 12))
                            .foregroundStyle(gw.opacity(0.35))
                            .padding(40)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(store.switchHistory.reversed()) { event in
                                    historyRow(event)
                                    Divider().background(gw.opacity(0.05))
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
            .frame(maxHeight: 420)
        }
    }

    private var tabDivider: some View {
        Divider().frame(height: 14).background(gw.opacity(0.08))
    }

    private func iconTab(_ icon: String, _ label: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 8, weight: selected ? .semibold : .regular))
            }
            .frame(minWidth: 44)
            .foregroundStyle(selected ? gw.opacity(0.8) : gw.opacity(0.32))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
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
            .frame(minHeight: 300)
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
            if store.staleProfileIds.contains(profile.id) {
                return .yellow
            }
            if store.rateLimits[profile.id] != nil {
                return .green
            }
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
                codexAvatar(size: 36, active: isActive)
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

                    // Rate limit rows
                    if let info = rl {
                        rateLimitRows(info: info)
                    } else if store.isFetchingLimits {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(height: 12)
                    }

                    // Token usage (show for all accounts with usage data)
                    if let u = usage, u.totalTokens > 0 {
                        tokenUsageRow(u)
                    }

                    // Cost
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

                    // Risk forecast
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
            .padding(.vertical, 10)
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

    // MARK: - Update Button

    private var updateButton: some View {
        Button {
            if store.availableUpdate != nil {
                store.openReleasePage()
            } else {
                store.checkForUpdates()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12, weight: .medium))
                    Text(L("Güncelle", "Update"))
                        .font(.system(size: 9, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(store.availableUpdate != nil ? Color.orange.opacity(0.85) : gw.opacity(0.52))
                .contentShape(Rectangle())

                if store.availableUpdate != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .offset(x: -4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider().background(gw.opacity(0.06))
            HStack(spacing: 0) {
                footerBtn("plus", Str.addAccount) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .addAccount }
                }
                    .disabled(store.isAddingAccount)
                thinDivider
                footerBtn("arrow.triangle.2.circlepath", Str.switchNow) { store.switchToNext() }
                    .disabled(store.profiles.count < 2)
                thinDivider
                footerBtn("clock.arrow.trianglehead.counterclockwise.rotate.90", Str.history) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .history }
                }
                thinDivider
                updateButton
                thinDivider
                footerBtn("power", Str.quit) { NSApplication.shared.terminate(nil) }
            }
            .frame(height: 44)

            settingsBar
        }
    }

    // MARK: - Settings Bar

    private var settingsBar: some View {
        let langLabel: String = {
            switch appLanguage {
            case "tr": return "TR"
            case "en": return "EN"
            default:   return Str.langAuto
            }
        }()

        return VStack(spacing: 0) {
            Divider().background(gw.opacity(0.04))
            HStack(spacing: 0) {
                // Language toggle: system → tr → en → system
                settingsBtn("globe", langLabel) {
                    if appLanguage == "system"   { appLanguage = "tr" }
                    else if appLanguage == "tr"  { appLanguage = "en" }
                    else                         { appLanguage = "system" }
                }
                thinDivider
                // Email blur
                settingsBtn(emailsBlurred ? "eye.slash" : "eye",
                            emailsBlurred ? Str.showEmail : Str.hideEmail) {
                    withAnimation(.easeInOut(duration: 0.2)) { emailsBlurred.toggle() }
                }
                thinDivider
                // Dark / Light
                settingsBtn(isDarkMode ? "moon.fill" : "sun.max",
                            isDarkMode ? Str.dark : Str.light) {
                    isDarkMode.toggle()
                }
                thinDivider
                // Reset token statistics
                settingsBtn("arrow.counterclockwise", L("Sıfırla", "Reset")) {
                    store.resetStatistics()
                }
            }
            .frame(height: 36)
        }
    }

    // MARK: - Shared Helpers

    private var thinDivider: some View {
        Divider().frame(height: 16).background(gw.opacity(0.07))
    }

    private func footerBtn(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(label).font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(gw.opacity(0.52))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func settingsBtn(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(gw.opacity(0.38))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
