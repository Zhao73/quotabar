import XCTest
@testable import CodexTokenCore

final class CodexWorkspaceSelectionTests: XCTestCase {
    func testDisplayedStorageKeyPrefersActiveCLIOverStaleSelectedAccount() {
        let accounts = [
            makeAccount(storageKey: "acct-active", isActiveCLI: true),
            makeAccount(storageKey: "acct-stale", isActiveCLI: false)
        ]

        let displayed = CodexWorkspaceSelection.displayedStorageKey(
            accounts: accounts,
            selectedStorageKey: "acct-stale",
            switchingStorageKey: nil
        )

        XCTAssertEqual(displayed, "acct-active")
    }

    func testDisplayedStorageKeyPrefersSwitchingTargetWhileSwitchIsInFlight() {
        let accounts = [
            makeAccount(storageKey: "acct-active", isActiveCLI: true),
            makeAccount(storageKey: "acct-target", isActiveCLI: false)
        ]

        let displayed = CodexWorkspaceSelection.displayedStorageKey(
            accounts: accounts,
            selectedStorageKey: "acct-target",
            switchingStorageKey: "acct-target"
        )

        XCTAssertEqual(displayed, "acct-target")
    }

    private func makeAccount(storageKey: String, isActiveCLI: Bool) -> CodexAccount {
        CodexAccount(
            id: storageKey,
            storageKey: storageKey,
            sourceFile: nil,
            accountID: storageKey,
            email: "\(storageKey)@example.com",
            loginProvider: nil,
            sortOrder: 0,
            displayName: storageKey,
            remark: nil,
            authMode: .chatGPT,
            lastRefreshAt: nil,
            isActiveCLI: isActiveCLI,
            isImportedFromActiveSession: false
        )
    }
}
