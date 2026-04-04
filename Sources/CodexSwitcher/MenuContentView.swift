import SwiftUI

enum NavScreen: Hashable { case main, history, addAccount }

struct MenuContentView: View {
    @EnvironmentObject var store: AppStore
    @State var hoveredId: UUID? = nil
    @State private var appeared = false
    @State var screen: NavScreen = .main
    @State var historyTab: HistoryTab = .list

    enum HistoryTab { case list, chart, projects, sessions, heatmap, expensive }

    @AppStorage("emailsBlurred") var emailsBlurred: Bool = false
    @AppStorage("isDarkMode")    var isDarkMode: Bool = true
    @AppStorage("appLanguage")   var appLanguage: String = "system"
    @Environment(\.colorScheme)  var scheme

    /// Adaptive foreground: white in dark mode, black in light mode
    var gw: Color { scheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: 0) {
            sideRail
            Divider().background(gw.opacity(0.06))

            VStack(spacing: 0) {
                navHeader
                switch screen {
                case .main:       mainContent
                case .history:    historyContent
                case .addAccount: addAccountContent
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
        // MARK: Keyboard Shortcuts ⌘1–⌘9
        .background(
            ForEach(Array(store.profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                Button("") {
                    guard profile.id != store.activeProfile?.id else { return }
                    store.switchTo(profile: profile)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .hidden()
            }
        )
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

    var mainContent: some View {
        VStack(spacing: 0) {
            analyticsQuickSummary
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var analyticsQuickSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Analitik", "Analytics"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.72))
                    Text(store.analyticsTimeRange.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(gw.opacity(0.28))
                }
                Spacer()
                Button {
                    store.openAnalyticsWindow()
                } label: {
                    Label(L("Aç", "Open"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(gw.opacity(0.64))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            HStack(spacing: 10) {
                quickMetric(label: L("Token", "Tokens"), value: formatTokens(store.analyticsSnapshot.summary.totalTokens))
                quickMetric(label: L("Maliyet", "Cost"),   value: CostCalculator.format(store.analyticsSnapshot.summary.estimatedTotalCost))
                quickMetric(label: L("Alert", "Alerts"),   value: "\(store.analyticsSnapshot.summary.activeAlertCount)")
            }

            if let message = store.analyticsSnapshot.dataQuality.message {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(gw.opacity(0.03))
    }

    private func quickMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(gw.opacity(0.25))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(gw.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var exhaustionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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

    // MARK: - Add Account Content

    var addAccountContent: some View {
        AddAccountInlineView().environmentObject(store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 10) {
            codexAvatar(size: 44, active: false)
            Text(Str.noAccounts)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Update Status Strip

    var updateStatusStrip: some View {
        HStack(spacing: 8) {
            if let pending = store.pendingSwitchRequest {
                Text(L("Sırada", "Queued"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.78))
                Text(pending.targetProfileName)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.34))
                Text("·").font(.system(size: 9)).foregroundStyle(gw.opacity(0.18))
            }
            if store.switchOrchestrationState == .verifying {
                Text(L("Doğrulanıyor", "Verifying"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.blue.opacity(0.72))
                Text("·").font(.system(size: 9)).foregroundStyle(gw.opacity(0.18))
            }

            Text("v\(store.updateStatus.currentVersion)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(gw.opacity(0.42))
            Text("→").font(.system(size: 9)).foregroundStyle(gw.opacity(0.18))
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

    // MARK: - Update State Helpers

    private var updateStateLabel: String {
        switch store.updateStatus.state {
        case .idle:            return Str.idle
        case .checking:        return Str.checking
        case .upToDate:        return L("Güncel", "Up to date")
        case .updateAvailable: return Str.updateAvailableShort
        case .failed:          return Str.failed
        }
    }

    private var updateStateColor: Color {
        switch store.updateStatus.state {
        case .idle:            return gw.opacity(0.3)
        case .checking:        return .blue
        case .upToDate:        return .green
        case .updateAvailable: return .orange
        case .failed:          return .red
        }
    }

    func compactTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Automation Confidence Helpers (used in AnalyticsWindowView)

    var automationConfidenceColor: Color {
        switch store.automationConfidence.status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var automationConfidenceIcon: String {
        switch store.automationConfidence.status {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .critical: return "bolt.shield.fill"
        }
    }

    var automationConfidenceLabel: String {
        switch store.automationConfidence.status {
        case .healthy: return Str.healthy
        case .warning: return Str.attention
        case .critical: return Str.critical
        }
    }

    func accountReliabilityColor(_ status: AccountReliabilityStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    func relativeShort(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
