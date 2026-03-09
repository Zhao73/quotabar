import SwiftUI

@main
struct CodexTokenApp: App {
    @StateObject private var preferences: AppPreferences
    @StateObject private var viewModel: CodexTokenMenuViewModel

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _viewModel = StateObject(wrappedValue: CodexTokenMenuViewModel(preferences: preferences))
    }

    var body: some Scene {
        MenuBarExtra {
            CodexTokenMenuView(viewModel: viewModel, preferences: preferences)
        } label: {
            Label(viewModel.menuBarTitle, systemImage: viewModel.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            CodexTokenSettingsView(viewModel: viewModel, preferences: preferences)
        }
    }
}
