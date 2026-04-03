import SwiftUI

struct SessionExplorerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var searchText = ""

    private var gw: Color { scheme == .dark ? .white : .black }

    private var filteredSessions: [SessionSummary] {
        guard !searchText.isEmpty else { return store.sessionSummaries }
        let q = searchText.lowercased()
        return store.sessionSummaries.filter {
            $0.firstPrompt.lowercased().contains(q) ||
            $0.projectName.lowercased().contains(q)
        }
    }

    /// Root sessions + their children grouped together
    private var trees: [(root: SessionSummary, children: [SessionSummary])] {
        let all = filteredSessions
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        var childrenOf: [String: [SessionSummary]] = [:]
        var roots: [SessionSummary] = []

        for session in all {
            if let parentId = session.parentId, byId[parentId] != nil {
                childrenOf[parentId, default: []].append(session)
            } else {
                roots.append(session)
            }
        }
        // Sort children by timestamp
        return roots.map { root in
            let children = (childrenOf[root.id] ?? []).sorted { $0.timestamp > $1.timestamp }
            return (root: root, children: children)
        }
    }

    var body: some View {
        if store.sessionSummaries.isEmpty {
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
                    ForEach(trees, id: \.root.id) { tree in
                        sessionRow(tree.root, indent: 0)
                        ForEach(tree.children) { child in
                            sessionRow(child, indent: 1)
                        }
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
