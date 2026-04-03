import Foundation

enum ProjectCSVExporter {
    static func buildCSV(for projects: [ProjectUsage]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = projects.map { project in
            [
                escaped(project.name),
                escaped(project.path),
                String(project.tokens),
                String(format: "%.4f", project.cost),
                String(project.sessionCount),
                escaped(formatter.string(from: project.lastUsed))
            ].joined(separator: ",")
        }

        return (["Project,Path,Tokens,Cost USD,Sessions,Last Used"] + rows).joined(separator: "\n") + "\n"
    }

    private static func escaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
