import AppKit
import CodexTokenCore
import Foundation

@MainActor
final class TerminalCLILaunchService {
    enum LaunchError: LocalizedError {
        case terminalOpenFailed(String)

        var errorDescription: String? {
            switch self {
            case let .terminalOpenFailed(message):
                return message
            }
        }
    }

    func launch(context: CLIProfileLaunchContext, accountLabel: String) throws {
        let scriptURL = context.codexHomeDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("launch.command")

        let codexHome = context.codexHomeDirectory.path.hasSuffix("/")
            ? context.codexHomeDirectory.path
            : context.codexHomeDirectory.path + "/"

        let script = """
        #!/bin/zsh
        export CODEX_HOME='\(escapeSingleQuotes(codexHome))'
        clear
        printf '\\e]1;CodexToken - \(escapeSingleQuotes(accountLabel))\\a'
        echo 'CodexToken account: \(escapeSingleQuotes(accountLabel))'
        echo 'CODEX_HOME: \(escapeSingleQuotes(codexHome))'
        echo
        exec codex
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LaunchError.terminalOpenFailed("Failed to open Terminal for the selected account.")
        }
    }

    private func escapeSingleQuotes(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}
