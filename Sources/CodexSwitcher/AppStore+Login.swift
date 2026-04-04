import Foundation
import AppKit

// MARK: - Login Process Management

extension AppStore {

    // MARK: CLI Path Discovery

    func findCLIPath(_ name: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which \(name)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = nil
        try? task.run()
        task.waitUntilExit()
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "/usr/local/bin/\(name)"
    }

    // MARK: Timeout

    func cancelLoginTimeout() {
        loginTimeout?.cancel()
        loginTimeout = nil
    }

    func loginTimedOut() {
        guard addingStep == .waitingLogin else { return }
        cancelLoginTimeout()
        stopCodexLoginProcess(suppressFailureFeedback: true)
        addingStep = .idle
        isAddingAccount = false
        addAccountErrorMessage = L("Login zaman aşımına uğradı. Tekrar deneyin.", "Login timed out. Please try again.")
        stopAuthWatcher()
    }

    // MARK: Start / Stop

    @discardableResult
    func startCodexLogin() -> Bool {
        stopCodexLoginProcess(suppressFailureFeedback: true)

        let codexPath = findCLIPath("codex")
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            isAddingAccount = false
            addingStep = .idle
            addAccountErrorMessage = L("`codex` komutu bulunamadı.", "`codex` command was not found.")
            sendNotification(
                title: L("Login başlatılamadı", "Login could not start"),
                body: L("`codex` komutu bulunamadı.", "`codex` command was not found.")
            )
            return false
        }

        let command = CodexLoginCommand.shellWrapped(codexPath: codexPath)
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: command.executablePath)
        task.arguments = command.arguments
        task.standardInput = nil
        task.standardOutput = pipe
        task.standardError = pipe

        loginOutputPipe = pipe
        loginOutputBuffer = ""
        didOpenLoginBrowser = false
        suppressLoginFailureFeedback = false

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.handleCodexLoginOutput(data) }
        }

        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleCodexLoginTermination(status: process.terminationStatus)
            }
        }

        do {
            try task.run()
            loginProcess = task
            return true
        } catch {
            stopCodexLoginProcess(suppressFailureFeedback: true)
            isAddingAccount = false
            addingStep = .idle
            addAccountErrorMessage = error.localizedDescription
            sendNotification(
                title: L("Login başlatılamadı", "Login could not start"),
                body: error.localizedDescription
            )
            return false
        }
    }

    func stopCodexLoginProcess(suppressFailureFeedback: Bool) {
        if suppressFailureFeedback { self.suppressLoginFailureFeedback = true }
        loginOutputPipe?.fileHandleForReading.readabilityHandler = nil
        loginOutputPipe = nil
        if let process = loginProcess, process.isRunning { process.terminate() }
        loginProcess = nil
        loginOutputBuffer = ""
        didOpenLoginBrowser = false
    }

    // MARK: Output / Termination Handlers

    private func handleCodexLoginOutput(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
        loginOutputBuffer += chunk

        guard !didOpenLoginBrowser,
              CodexLoginOutputParser.authorizationURL(in: loginOutputBuffer) != nil else { return }
        didOpenLoginBrowser = true
    }

    private func handleCodexLoginTermination(status: Int32) {
        guard loginProcess != nil else { return }
        let shouldReportFailure = status != 0 && !suppressLoginFailureFeedback && addingStep == .waitingLogin

        stopCodexLoginProcess(suppressFailureFeedback: true)

        if shouldReportFailure {
            cancelLoginTimeout()
            isAddingAccount = false
            addingStep = .idle
            stopAuthWatcher()
            addAccountErrorMessage = L(
                "Codex login süreci erken kapandı. Tarayıcı bağlantısı üretilemedi.",
                "Codex login exited early before it could provide a browser link."
            )
            sendNotification(
                title: L("Login başlatılamadı", "Login could not start"),
                body: L("Codex login süreci erken kapandı. Browser linki üretilemedi.", "Codex login exited early before it could provide a browser link.")
            )
        }
    }
}
