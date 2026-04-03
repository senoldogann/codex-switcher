import SwiftUI

struct SessionExplorerTreeBuilder {
    struct Row: Identifiable {
        let session: SessionSummary
        let indent: Int

        var id: String { session.id }
    }

    static func flatten(_ sessions: [SessionSummary]) -> [Row] {
        let byId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let childrenOf = Dictionary(grouping: sessions) { $0.parentId }
        let roots = sessions
            .filter { session in
                guard let parentId = session.parentId else { return true }
                return byId[parentId] == nil
            }
            .sorted { $0.timestamp > $1.timestamp }

        var flattened: [Row] = []
        for root in roots {
            append(session: root, indent: 0, childrenOf: childrenOf, into: &flattened)
        }
        return flattened
    }

    private static func append(
        session: SessionSummary,
        indent: Int,
        childrenOf: [String?: [SessionSummary]],
        into flattened: inout [Row]
    ) {
        flattened.append(Row(session: session, indent: indent))
        let children = (childrenOf[session.id] ?? []).sorted { $0.timestamp > $1.timestamp }
        for child in children {
            append(session: child, indent: indent + 1, childrenOf: childrenOf, into: &flattened)
        }
    }
}

struct SessionExplorerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var searchText = ""

    private var gw: Color { scheme == .dark ? .white : .black }

    private var filteredSessions: [SessionSummary] {
        guard !searchText.isEmpty else { return store.analyticsSnapshot.sessions }
        let q = searchText.lowercased()
        return store.analyticsSnapshot.sessions.filter {
            $0.firstPrompt.lowercased().contains(q) ||
            $0.projectName.lowercased().contains(q)
        }
    }

    private var rows: [SessionExplorerTreeBuilder.Row] {
        SessionExplorerTreeBuilder.flatten(filteredSessions)
    }

    var body: some View {
        if store.analyticsSnapshot.sessions.isEmpty {
            Text(L("Veri yok", "No data yet"))
                .font(.system(size: 12))
                .foregroundStyle(gw.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(gw.opacity(0.3))
                    TextField(L("Ara…", "Search…"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(gw.opacity(0.75))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(gw.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(gw.opacity(0.05), in: .rect(cornerRadius: 6))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        sessionRow(row.session, indent: row.indent)
                        Divider().background(gw.opacity(0.05))
                    }
                }
                .padding(.bottom, 8)
            }
            } // close outer VStack
        }
    }

    private func sessionRow(_ session: SessionSummary, indent: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Thread indent line
            if indent > 0 {
                Rectangle()
                    .fill(gw.opacity(0.1))
                    .frame(width: 1)
                    .padding(.leading, 20)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    // Project badge
                    Text(session.projectName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(gw.opacity(0.55))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(gw.opacity(0.08))
                        .clipShape(Capsule())

                    // Role badge (only for sub-agents)
                    if session.depth > 0 {
                        roleBadge(session.agentRole)
                    }

                    Spacer(minLength: 0)

                    Text(session.timestamp, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(gw.opacity(0.25))
                }

                if !session.firstPrompt.isEmpty {
                    Text(session.firstPrompt)
                        .font(.system(size: 10))
                        .foregroundStyle(gw.opacity(indent > 0 ? 0.4 : 0.65))
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if session.tokens > 0 {
                        Label(formatTokens(session.tokens), systemImage: "cpu")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(gw.opacity(0.3))
                    }
                    if session.depth > 0 {
                        Label("depth \(session.depth)", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 9))
                            .foregroundStyle(gw.opacity(0.22))
                    }
                }
            }
        }
        .padding(.leading, indent > 0 ? 14 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(indent > 0 ? gw.opacity(0.02) : Color.clear)
    }

    @ViewBuilder
    private func roleBadge(_ role: String) -> some View {
        let (color, icon): (Color, String) = {
            switch role {
            case "reviewer":  return (.blue,   "checkmark.circle")
            case "explorer":  return (.green,  "binoculars")
            case "worker":    return (.orange, "wrench")
            default:          return (.purple, "cpu")
            }
        }()

        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
            Text(role)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(color.opacity(0.85))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
