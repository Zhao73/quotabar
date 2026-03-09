import AppIntents
import AppKit
import CodexTokenCore

struct SaveCurrentSessionSnapshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Current Session Snapshot"
    static let description = IntentDescription(
        "Copies the active ~/.codex/auth.json session into the local accounts snapshot directory."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let destination = try AccountSnapshotImportService().importCurrentSessionSnapshot(preferredFileName: nil)
        return .result(dialog: IntentDialog("Saved \(destination.lastPathComponent)."))
    }
}

struct OpenCodexDirectoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Codex Directory"
    static let description = IntentDescription("Opens the local ~/.codex folder in Finder.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        NSWorkspace.shared.open(CodexPaths.live().codexDirectory)
        return .result(dialog: IntentDialog("Opened the .codex folder."))
    }
}

struct RevealActiveAuthFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Reveal Active Auth File"
    static let description = IntentDescription("Reveals the active ~/.codex/auth.json file in Finder.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let authFile = CodexPaths.live().activeAuthFile
        guard FileManager.default.fileExists(atPath: authFile.path) else {
            throw AccountSnapshotImportError.activeAuthMissing
        }
        NSWorkspace.shared.activateFileViewerSelecting([authFile])
        return .result(dialog: IntentDialog("Revealed auth.json in Finder."))
    }
}

struct CodexTokenShortcutsProvider: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveCurrentSessionSnapshotIntent(),
            phrases: ["Save the current Codex session in \(.applicationName)"],
            shortTitle: "Save Session",
            systemImageName: "square.and.arrow.down"
        )
        AppShortcut(
            intent: OpenCodexDirectoryIntent(),
            phrases: ["Open the Codex directory in \(.applicationName)"],
            shortTitle: "Open .codex",
            systemImageName: "folder"
        )
        AppShortcut(
            intent: RevealActiveAuthFileIntent(),
            phrases: ["Reveal the active Codex auth file in \(.applicationName)"],
            shortTitle: "Reveal auth.json",
            systemImageName: "doc.text"
        )
    }
}
