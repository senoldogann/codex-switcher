import Foundation
import Testing
@testable import CodexSwitcher

struct CodexStateStoreTests {
    @Test
    func loadWorkflowSummaryReadsRecentThreadsAndRepoInsights() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let databaseURL = baseDirectory.appendingPathComponent("state_5.sqlite")
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let updatedAt = Int(now.timeIntervalSince1970)

        try runSQL(
            """
            create table threads (
              id text primary key,
              rollout_path text not null,
              created_at integer not null,
              updated_at integer not null,
              source text not null,
              model_provider text not null,
              cwd text not null,
              title text not null,
              sandbox_policy text not null,
              approval_mode text not null,
              tokens_used integer not null default 0,
              has_user_event integer not null default 0,
              archived integer not null default 0,
              archived_at integer,
              git_sha text,
              git_branch text,
              git_origin_url text,
              cli_version text not null default '',
              first_user_message text not null default '',
              agent_nickname text,
              agent_role text,
              memory_mode text not null default 'enabled',
              model text,
              reasoning_effort text,
              agent_path text
            );
            create table thread_spawn_edges (
              parent_thread_id text not null,
              child_thread_id text not null primary key,
              status text not null
            );
            insert into threads values (
              'thread-1', '', \(updatedAt - 50), \(updatedAt - 10), 'desktop', 'openai',
              '/tmp/demo-repo', 'Investigate limits', 'workspace-write', 'never', 1200, 1, 0, null,
              null, 'main', null, '1.0.0', '', null, 'worker', 'enabled', 'gpt-5.4', null, null
            );
            insert into threads values (
              'thread-2', '', \(updatedAt - 100), \(updatedAt - 20), 'desktop', 'openai',
              '/tmp/demo-repo', 'Check fallback', 'workspace-write', 'never', 800, 1, 0, null,
              null, 'main', null, '1.0.0', '', null, '', 'enabled', 'gpt-5.3-codex', null, null
            );
            insert into thread_spawn_edges values ('thread-1', 'thread-2', 'open');
            """,
            databaseURL: databaseURL
        )

        let store = CodexStateStore(sqlitePath: databaseURL.path, shellPath: "/bin/zsh")
        let summary = store.loadWorkflowSummary(range: .sevenDays, now: now)

        #expect(summary.totalActiveThreads == 2)
        #expect(summary.totalThreadTokens == 2000)
        #expect(summary.openSpawnEdges == 1)
        #expect(summary.repoInsights.first?.displayName == "demo-repo")
        #expect(summary.recentThreads.first?.threadId == "thread-1")
    }

    private func runSQL(_ sql: String, databaseURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "sqlite3 '\(databaseURL.path)' <<'SQL'\n\(sql)\nSQL"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
