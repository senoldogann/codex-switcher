import Testing
@testable import CodexSwitcher

struct CodexLoginCommandTests {
    @Test
    func shellWrappedUsesLoginShellInvocation() {
        let command = CodexLoginCommand.shellWrapped(codexPath: "/opt/homebrew/bin/codex")

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments == ["-l", "-c", "exec '/opt/homebrew/bin/codex' login"])
    }
}
