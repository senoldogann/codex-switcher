import SwiftUI

// MARK: - Profile Row

extension MenuContentView {

    var separator: some View {
        Divider()
            .background(gw.opacity(0.06))
            .padding(.leading, 60)
    }

    func healthDot(for profile: Profile) -> some View {
        let color: Color = {
            if store.staleProfileIds.contains(profile.id) { return .yellow }
            if store.rateLimits[profile.id] != nil { return .green }
            return .gray
        }()
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    func profileRow(_ profile: Profile) -> some View {
        let isActive = profile.id == store.activeProfile?.id
        let rl    = store.rateLimit(for: profile)
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
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                                .shadow(color: store.isSessionActive ? .green : .clear, radius: 4)
                                .opacity(store.isSessionActive ? 0.8 : 0.5)
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
                        ProgressView().scaleEffect(0.5).frame(height: 12)
                    }

                    if let health = store.rateLimitHealth[profile.id],
                       let line = healthLine(for: health, profileId: profile.id) {
                        Text(line)
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

    // MARK: Rate Limit Rows

    @ViewBuilder
    func rateLimitRows(info: RateLimitInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pct = info.weeklyRemainingPercent {
                limitRow(label: Str.weekly, percent: pct, resetLabel: info.weeklyResetLabel,
                         critical: pct <= 15, isRemaining: true)
            }
            if info.isPlus, let pct = info.fiveHourRemainingPercent {
                limitRow(label: Str.fiveHour, percent: pct, resetLabel: info.fiveHourResetLabel,
                         critical: pct <= 15, isRemaining: true)
            }
        }
    }

    func limitRow(label: String, percent: Int, resetLabel: String, critical: Bool, isRemaining: Bool = false) -> some View {
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

    // MARK: Token Usage Row

    func tokenUsageRow(_ u: AccountTokenUsage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 8))
                .foregroundStyle(gw.opacity(0.3))
            Text("\(formatTokens(u.totalTokens)) tokens")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(gw.opacity(0.32))
            if let topModel = u.modelUsage.max(by: { $0.value.totalTokens < $1.value.totalTokens })?.key {
                Text("· \(topModel)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.22))
            }
            if u.cachedInputTokens > 0 {
                Text("·").foregroundStyle(gw.opacity(0.2))
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

    func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: Avatar

    func profileAvatar(_ profile: Profile, size: CGFloat, active: Bool) -> some View {
        codexAvatar(size: size, active: active)
    }

    func codexAvatar(size: CGFloat, active: Bool) -> some View {
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

    func loadCodexIcon() -> NSImage? {
        if let url = Bundle.appResources.url(forResource: "codex", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    // MARK: Health Line

    func healthLine(for health: RateLimitHealthStatus, profileId: UUID) -> String? {
        if store.staleProfileIds.contains(profileId) {
            var parts: [String] = [Str.stale]
            if let reason = health.staleReason?.summary { parts.append(reason) }
            if let lastOk = health.lastSuccessfulFetchAt { parts.append("\(Str.lastOk) \(compactTime(lastOk))") }
            return parts.joined(separator: " · ")
        }
        if let failure = health.failureSummary {
            var parts: [String] = [failure]
            if let code = health.lastHTTPStatusCode { parts.append("HTTP \(code)") }
            if let lastOk = health.lastSuccessfulFetchAt { parts.append("\(Str.lastOk) \(compactTime(lastOk))") }
            return parts.joined(separator: " · ")
        }
        return nil
    }
}
