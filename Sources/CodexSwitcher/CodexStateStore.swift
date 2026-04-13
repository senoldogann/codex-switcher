import Foundation

final class CodexStateStore: @unchecked Sendable {
    private let sqlitePath: String
    private let shellPath: String

    init(sqlitePath: String, shellPath: String) {
        self.sqlitePath = sqlitePath
        self.shellPath = shellPath
    }

    convenience init() {
        self.init(
            sqlitePath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/state_5.sqlite")
                .path,
            shellPath: "/bin/zsh"
        )
    }

    func loadWorkflowSummary(range: AnalyticsTimeRange, now: Date) -> WorkflowSummary {
        guard FileManager.default.fileExists(atPath: sqlitePath) else {
            return .empty
        }

        let cutoff = range.cutoffDate(from: now).map { Int($0.timeIntervalSince1970) } ?? 0
        let recentThreads = loadRecentThreads(cutoff: cutoff)
        let repoInsights = loadRepoInsights(cutoff: cutoff)
        let openSpawnEdges = loadOpenSpawnEdges()

        return WorkflowSummary(
            totalActiveThreads: recentThreads.count,
            totalThreadTokens: recentThreads.reduce(0) { $0 + $1.tokensUsed },
            openSpawnEdges: openSpawnEdges,
            repoInsights: repoInsights,
            recentThreads: recentThreads
        )
    }

    private func loadRecentThreads(cutoff: Int) -> [WorkflowThreadRecord] {
        let query = """
        sqlite3 -readonly -separator $'\\t' '\(sqlitePath)' "
        select
          id,
          substr(replace(replace(coalesce(title, ''), char(10), ' '), char(9), ' '), 1, 120),
          replace(replace(coalesce(cwd, ''), char(10), ' '), char(9), ' '),
          coalesce(git_branch, ''),
          coalesce(model, ''),
          coalesce(agent_role, ''),
          tokens_used,
          updated_at
        from threads
        where archived = 0 and updated_at >= \(cutoff)
        order by updated_at desc
        limit 8;
        "
        """

        return runQuery(query).compactMap { row in
            guard row.count == 8,
                  let tokensUsed = Int(row[6]),
                  let updatedAtSeconds = TimeInterval(row[7]) else {
                return nil
            }
            return WorkflowThreadRecord(
                threadId: row[0],
                titlePreview: row[1].isEmpty ? "Untitled thread" : row[1],
                cwd: row[2],
                gitBranch: row[3],
                model: row[4],
                agentRole: row[5],
                tokensUsed: tokensUsed,
                updatedAt: Date(timeIntervalSince1970: updatedAtSeconds)
            )
        }
    }

    private func loadRepoInsights(cutoff: Int) -> [WorkflowRepoInsight] {
        let query = """
        sqlite3 -readonly -separator $'\\t' '\(sqlitePath)' "
        select
          replace(replace(coalesce(cwd, ''), char(10), ' '), char(9), ' '),
          count(*),
          sum(tokens_used),
          max(updated_at)
        from threads
        where archived = 0 and updated_at >= \(cutoff)
        group by cwd
        order by sum(tokens_used) desc
        limit 5;
        "
        """

        return runQuery(query).compactMap { row in
            guard row.count == 4,
                  let threadCount = Int(row[1]),
                  let totalTokens = Int(row[2]),
                  let updatedAtSeconds = TimeInterval(row[3]) else {
                return nil
            }
            let displayName = URL(fileURLWithPath: row[0]).lastPathComponent
            return WorkflowRepoInsight(
                cwd: row[0],
                displayName: displayName.isEmpty ? row[0] : displayName,
                threadCount: threadCount,
                totalTokens: totalTokens,
                latestActivityAt: Date(timeIntervalSince1970: updatedAtSeconds)
            )
        }
    }

    private func loadOpenSpawnEdges() -> Int {
        let query = """
        sqlite3 -readonly -separator $'\\t' '\(sqlitePath)' "
        select count(*) from thread_spawn_edges where status = 'open';
        "
        """
        return runQuery(query).first.flatMap(\.first).flatMap(Int.init) ?? 0
    }

    private func runQuery(_ query: String) -> [[String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", query]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output
                .split(separator: "\n")
                .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        } catch {
            return []
        }
    }
}
