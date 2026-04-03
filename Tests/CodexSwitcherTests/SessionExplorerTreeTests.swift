import Foundation
import Testing
@testable import CodexSwitcher

struct SessionExplorerTreeTests {
    @Test
    func flattenIncludesNestedDescendantsInDepthFirstOrder() {
        let now = Date()
        let root = SessionSummary(
            id: "root",
            projectName: "Demo",
            projectPath: "/tmp/demo",
            firstPrompt: "root prompt",
            tokens: 10,
            timestamp: now,
            depth: 0,
            agentRole: "default",
            parentId: nil
        )
        let child = SessionSummary(
            id: "child",
            projectName: "Demo",
            projectPath: "/tmp/demo",
            firstPrompt: "child prompt",
            tokens: 5,
            timestamp: now.addingTimeInterval(-10),
            depth: 1,
            agentRole: "worker",
            parentId: "root"
        )
        let grandchild = SessionSummary(
            id: "grandchild",
            projectName: "Demo",
            projectPath: "/tmp/demo",
            firstPrompt: "grandchild prompt",
            tokens: 3,
            timestamp: now.addingTimeInterval(-20),
            depth: 2,
            agentRole: "reviewer",
            parentId: "child"
        )

        let flattened = SessionExplorerTreeBuilder.flatten([grandchild, child, root])

        #expect(flattened.map(\.session.id) == ["root", "child", "grandchild"])
        #expect(flattened.map(\.indent) == [0, 1, 2])
    }
}
