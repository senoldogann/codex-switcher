import SwiftUI

// MARK: - History Content

extension MenuContentView {

    var historyContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                iconTab("list.bullet",                  L("Geçmiş", "History"),   historyTab == .list)      { historyTab = .list }
                tabDivider
                iconTab("chart.line.uptrend.xyaxis",    L("Grafik", "Chart"),     historyTab == .chart)     { historyTab = .chart }
                tabDivider
                iconTab("folder.fill",                  L("Projeler", "Projects"), historyTab == .projects) { historyTab = .projects }
                tabDivider
                iconTab("bubble.left.and.bubble.right", L("Oturumlar", "Sess."),  historyTab == .sessions)  { historyTab = .sessions }
                tabDivider
                iconTab("square.grid.2x2",              L("Isı", "Heatmap"),      historyTab == .heatmap)   { historyTab = .heatmap }
                tabDivider
                iconTab("flame.fill",                   L("Pahalı", "Top $"),     historyTab == .expensive) { historyTab = .expensive }
            }
            .frame(height: 38)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 2)

            analyticsRangeBar
            switchReliabilitySummary
            Divider().background(gw.opacity(0.06))

            Group {
                switch historyTab {
                case .list:
                    if store.switchHistory.isEmpty && store.switchTimeline.isEmpty && store.switchDecisionHistory.isEmpty {
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
                                if !store.switchDecisionHistory.isEmpty {
                                    sectionLabel(L("Kararlar", "Decisions"))
                                    ForEach(Array(store.switchDecisionHistory.reversed().prefix(8))) { decision in
                                        decisionRow(decision)
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

    var tabDivider: some View {
        Divider().frame(height: 18).background(gw.opacity(0.08))
    }

    var analyticsRangeBar: some View {
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

    var switchReliabilitySummary: some View {
        HStack(spacing: 10) {
            summaryPill(label: Str.queued,   value: "\(store.switchReliability.pendingSwitchCount)",   tint: .orange)
            summaryPill(label: Str.seamless, value: "\(store.switchReliability.seamlessSuccessCount)", tint: .green)
            summaryPill(label: Str.fallback, value: "\(store.switchReliability.fallbackRestartCount)", tint: .blue)
            summaryPill(label: L("Blok", "Blocked"), value: "\(store.switchReliability.blockedDecisionCount)", tint: .red)
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

    func iconTab(_ icon: String, _ label: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
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

    // MARK: Row Views

    func historyRow(_ event: SwitchEvent) -> some View {
        let isAuto = event.reason.contains("Limit") || event.reason.contains("doldu")
        let iconName: String = isAuto ? "bolt.fill" : "arrow.left.arrow.right"
        let iconColor: Color = isAuto ? .orange : .blue

        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 26, height: 26)
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

    func timelineRow(_ event: SwitchTimelineEvent) -> some View {
        let iconName: String = {
            switch event.stage {
            case .queued:         return "pause.circle.fill"
            case .ready:          return "checkmark.circle"
            case .verifying:      return "ellipsis.circle"
            case .seamlessSuccess: return "bolt.horizontal.circle.fill"
            case .fallbackRestart: return "arrow.clockwise.circle.fill"
            case .inconclusive:   return "questionmark.circle"
            case .blocked:        return "xmark.circle.fill"
            case .halted:         return "stop.circle.fill"
            }
        }()
        let tint: Color = {
            switch event.stage {
            case .queued:         return .orange
            case .ready:          return .yellow
            case .verifying:      return .blue
            case .seamlessSuccess: return .green
            case .fallbackRestart: return .blue
            case .inconclusive:   return gw
            case .blocked:        return .red
            case .halted:         return .pink
            }
        }()

        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 26, height: 26)
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

    func decisionRow(_ decision: SwitchDecisionRecord) -> some View {
        let tint = decisionOutcomeColor(decision.outcome)
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 26, height: 26)
                Image(systemName: decisionOutcomeIcon(decision.outcome))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(decisionOutcomeLabel(decision.outcome))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.74))
                    if let chosen = decision.chosenProfileName {
                        Text(chosen)
                            .font(.system(size: 10))
                            .foregroundStyle(gw.opacity(0.42))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(decision.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.24))
                }
                Text(decision.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    metricCapsule(label: Str.reason, value: decision.reason)
                    metricCapsule(label: L("Kaynak", "Source"), value: decision.source.rawValue)
                    if decision.overrideApplied {
                        metricCapsule(label: L("Override", "Override"), value: L("Evet", "Yes"))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared Helpers

    func sectionLabel(_ text: String) -> some View {
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

    func summaryPill(label: String, value: String, tint: Color) -> some View {
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
        .background(Capsule().fill(gw.opacity(0.05)))
    }

    func metricCapsule(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 8)).foregroundStyle(gw.opacity(0.22))
            Text(value).font(.system(size: 8, weight: .medium)).foregroundStyle(gw.opacity(0.42)).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(gw.opacity(0.05)))
    }

    func switchOutcomeLabel(_ outcome: SeamlessSwitchResult.Outcome) -> String {
        switch outcome {
        case .deferred:        return Str.deferred
        case .seamlessSuccess: return L("Doğrulandı", "Verified")
        case .fallbackRestart: return Str.fallbackRestart
        case .inconclusive:    return Str.inconclusive
        }
    }

    func switchOutcomeColor(_ outcome: SeamlessSwitchResult.Outcome) -> Color {
        switch outcome {
        case .deferred:        return .orange
        case .seamlessSuccess: return .green
        case .fallbackRestart: return .blue
        case .inconclusive:    return gw
        }
    }

    func timelineStageLabel(_ stage: SwitchTimelineEvent.Stage) -> String {
        switch stage {
        case .queued:         return L("Kuyrukta", "Queued")
        case .ready:          return L("Hazır", "Ready")
        case .verifying:      return L("Doğrulanıyor", "Verifying")
        case .seamlessSuccess: return Str.seamless
        case .fallbackRestart: return Str.fallbackRestart
        case .inconclusive:   return Str.inconclusive
        case .blocked:        return L("Bloklandı", "Blocked")
        case .halted:         return L("Durdu", "Halted")
        }
    }

    func decisionOutcomeLabel(_ outcome: SwitchDecisionOutcome) -> String {
        switch outcome {
        case .queued:         return L("Kuyruğa alındı", "Queued")
        case .executed:       return L("Çalıştırıldı", "Executed")
        case .blocked:        return L("Bloklandı", "Blocked")
        case .halted:         return L("Durdu", "Halted")
        case .manualOverride: return L("Manuel override", "Manual override")
        }
    }

    func decisionOutcomeIcon(_ outcome: SwitchDecisionOutcome) -> String {
        switch outcome {
        case .queued:         return "pause.circle.fill"
        case .executed:       return "checkmark.circle.fill"
        case .blocked:        return "xmark.circle.fill"
        case .halted:         return "stop.circle.fill"
        case .manualOverride: return "exclamationmark.triangle.fill"
        }
    }

    func decisionOutcomeColor(_ outcome: SwitchDecisionOutcome) -> Color {
        switch outcome {
        case .queued:         return .orange
        case .executed:       return .green
        case .blocked:        return .red
        case .halted:         return .pink
        case .manualOverride: return .yellow
        }
    }
}
