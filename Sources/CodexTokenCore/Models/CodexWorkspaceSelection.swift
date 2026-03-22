import Foundation

public enum CodexWorkspaceSelection {
    public static func displayedStorageKey(
        accounts: [CodexAccount],
        selectedStorageKey: String?,
        switchingStorageKey: String?
    ) -> String? {
        if let switchingStorageKey,
           accounts.contains(where: { $0.storageKey == switchingStorageKey }) {
            return switchingStorageKey
        }

        if let activeStorageKey = accounts.first(where: \.isActiveCLI)?.storageKey {
            return activeStorageKey
        }

        if let selectedStorageKey,
           accounts.contains(where: { $0.storageKey == selectedStorageKey }) {
            return selectedStorageKey
        }

        return accounts.first?.storageKey
    }
}
