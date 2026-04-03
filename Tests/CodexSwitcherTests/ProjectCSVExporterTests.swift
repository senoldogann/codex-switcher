import Foundation
import Testing
@testable import CodexSwitcher

struct ProjectCSVExporterTests {
    @Test
    func buildCSVQuotesFieldsAndFormatsRows() {
        let projects = [
            ProjectUsage(
                id: "/tmp/project",
                name: #"demo "project""#,
                path: "/tmp/project",
                tokens: 12345,
                cost: 4.3125,
                sessionCount: 3,
                lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]

        let csv = ProjectCSVExporter.buildCSV(for: projects)

        #expect(csv.contains("Project,Path,Tokens,Cost USD,Sessions,Last Used"))
        #expect(csv.contains(#""demo ""project"""#))
        #expect(csv.contains(#""/tmp/project",12345,4.3125,3,"#))
        #expect(csv.hasSuffix("\n"))
    }
}
