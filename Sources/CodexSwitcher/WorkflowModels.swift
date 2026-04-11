import Foundation

struct WorkflowThreadRecord: Equatable, Sendable {
    let threadId: String
    let titlePreview: String
    let cwd: String
    let gitBranch: String
    let model: String
    let agentRole: String
    let tokensUsed: Int
    let updatedAt: Date
}

struct WorkflowRepoInsight: Identifiable, Equatable, Sendable {
    var id: String { cwd }

    let cwd: String
    let displayName: String
    let threadCount: Int
    let totalTokens: Int
    let latestActivityAt: Date
}

struct WorkflowSummary: Equatable, Sendable {
    let totalActiveThreads: Int
    let totalThreadTokens: Int
    let openSpawnEdges: Int
    let repoInsights: [WorkflowRepoInsight]
    let recentThreads: [WorkflowThreadRecord]

    static let empty = WorkflowSummary(
        totalActiveThreads: 0,
        totalThreadTokens: 0,
        openSpawnEdges: 0,
        repoInsights: [],
        recentThreads: []
    )
}
