import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProjectBreakdownView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @State private var drillProject: String? = nil  // projectPath when drilling in

    private var gw: Color { scheme == .dark ? .white : .black }

    private var maxTokens: Int {
        store.analyticsSnapshot.projects.first?.tokens ?? 1
    }

    var body: some View {
        if store.analyticsSnapshot.projects.isEmpty {
            Text(L("Veri yok", "No data yet"))
                .font(.system(size: 12))
                .foregroundStyle(gw.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(40)
        } else if let drillPath = drillProject {
            drillDownView(for: drillPath)
        } else {
            projectListView
        }
    }

    // MARK: - Project List

    private var projectListView: some View {
        VStack(spacing: 0) {
            // Export button
            HStack {
                Spacer()
                Button {
                    exportCSV()
                } label: {
                    Label(L("CSV", "CSV"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(gw.opacity(0.35))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .padding(.trailing, 14)
                .padding(.top, 6)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(store.analyticsSnapshot.projects) { project in
                        projectRow(project)
                        Divider().background(gw.opacity(0.05))
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Drill-down: sessions for a project

    private func drillDownView(for path: String) -> some View {
        let name = store.analyticsSnapshot.projects.first(where: { $0.path == path })?.name ?? path
        let sessions = store.analyticsSnapshot.sessions.filter { $0.projectPath == path }

        return VStack(spacing: 0) {
            // Back + title
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { drillProject = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.4))
                }
                .buttonStyle(.plain).pointerCursor()

                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.7))
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                Text(L("\(sessions.count) oturum", "\(sessions.count) sessions"))
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().background(gw.opacity(0.06))

            if sessions.isEmpty {
                Text(L("Bu proje için oturum verisi yok.", "No session data for this project."))
                    .font(.system(size: 11))
                    .foregroundStyle(gw.opacity(0.3))
                    .padding(24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sessions) { session in
                            drillSessionRow(session)
                            Divider().background(gw.opacity(0.05))
                        }
                    }
                }
            }
        }
    }

    private func drillSessionRow(_ session: SessionSummary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Role / depth indicator
            if session.depth > 0 {
                Text(session.agentRole)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.blue.opacity(0.7))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.blue.opacity(0.08), in: .capsule)
            } else {
                Image(systemName: "bubble.left")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 3) {
                if !session.firstPrompt.isEmpty {
                    Text(session.firstPrompt)
                        .font(.system(size: 10))
                        .foregroundStyle(gw.opacity(0.65))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if session.tokens > 0 {
                        Text(formatTokens(session.tokens) + " tok")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(gw.opacity(0.3))
                    }
                    Text(session.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.22))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportCSV() {
        let csv = ProjectCSVExporter.buildCSV(for: store.analyticsSnapshot.projects)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codex-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
        }
    }

    private func projectRow(_ project: ProjectUsage) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { drillProject = project.path }
        } label: { projectRowContent(project) }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func projectRowContent(_ project: ProjectUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.7))

                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(gw.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(formatTokens(project.tokens))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.55))

                Text(CostCalculator.format(project.cost))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.35))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(gw.opacity(0.06))
                    Capsule()
                        .fill(barGradient(for: project))
                        .frame(width: max(4, geo.size.width * barFraction(project.tokens)))
                }
            }
            .frame(height: 4)

            HStack(spacing: 8) {
                Label("\(project.sessionCount) sess", systemImage: "bubble.left")
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.3))

                Text(project.path)
                    .font(.system(size: 9))
                    .foregroundStyle(gw.opacity(0.2))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barFraction(_ tokens: Int) -> CGFloat {
        guard maxTokens > 0 else { return 0 }
        return CGFloat(tokens) / CGFloat(maxTokens)
    }

    private func barGradient(for project: ProjectUsage) -> LinearGradient {
        let fraction = barFraction(project.tokens)
        if fraction > 0.7 {
            return LinearGradient(colors: [.orange.opacity(0.8), .red.opacity(0.6)],
                                  startPoint: .leading, endPoint: .trailing)
        } else if fraction > 0.35 {
            return LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.5)],
                                  startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [gw.opacity(0.4), gw.opacity(0.25)],
                                  startPoint: .leading, endPoint: .trailing)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
