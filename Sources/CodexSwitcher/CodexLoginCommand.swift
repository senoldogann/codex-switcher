import Foundation

struct CodexLoginCommand: Equatable {
    let executablePath: String
    let arguments: [String]

    static func shellWrapped(codexPath: String) -> CodexLoginCommand {
        let escapedPath = codexPath.replacingOccurrences(of: "'", with: "'\"'\"'")
        return CodexLoginCommand(
            executablePath: "/bin/zsh",
            arguments: ["-l", "-c", "exec '\(escapedPath)' login"]
        )
    }
}
