import AppKit
import CodexTokenCore
import SwiftUI

struct CodexTokenSettingsView: View {
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    @ObservedObject var preferences: AppPreferences
    @State private var pendingDeletion: CodexAccount?

    var body: some View {
        Form {
            accountsSection
            languageSection
            experimentalSection
            storageSection
            actionsSection
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 580)
    }

    private var accountsSection: some View {
        Section {
            ForEach(viewModel.accountRows) { row in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.account.email ?? row.account.displayName)
                            .font(.headline)
                        Text("\(row.account.accountID ?? preferences.string("menu.account.identifierMissing")) • \(row.account.loginProvider ?? preferences.string("meta.authMode.unknown"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        pendingDeletion = row.account
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help(preferences.string("settings.accounts.delete"))
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(preferences.string("settings.accounts.section"))
        }
        .alert(item: $pendingDeletion) { account in
            Alert(
                title: Text(preferences.string("settings.accounts.deleteConfirmTitle")),
                message: Text(
                    String(
                        format: preferences.string("settings.accounts.deleteConfirmMessage"),
                        account.email ?? account.displayName
                    )
                ),
                primaryButton: .destructive(Text(preferences.string("settings.accounts.delete"))) {
                    viewModel.deleteAccount(account)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var languageSection: some View {
        Section {
            Picker(
                preferences.string("settings.language.label"),
                selection: $preferences.language
            ) {
                Text(preferences.string("settings.language.system")).tag(AppLanguage.system)
                Text(preferences.string("settings.language.english")).tag(AppLanguage.english)
                Text(preferences.string("settings.language.simplifiedChinese")).tag(AppLanguage.simplifiedChinese)
            }
            Text(preferences.string("settings.language.help"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text(preferences.string("settings.language.section"))
        }
    }

    private var experimentalSection: some View {
        Section {
            Toggle(
                preferences.string("settings.experimental.quotaToggle"),
                isOn: $preferences.experimentalQuotaEnabled
            )
            TextField(
                preferences.string("settings.experimental.commandLabel"),
                text: $preferences.experimentalQuotaCommand
            )
            .textFieldStyle(.roundedBorder)
            .disabled(!preferences.experimentalQuotaEnabled)

            Text(preferences.string("settings.experimental.commandHelp"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text(preferences.string("settings.experimental.section"))
        }
    }

    private var storageSection: some View {
        Section {
            pathRow(
                label: preferences.string("settings.storage.codexDirectory"),
                value: viewModel.paths.codexDirectory.path
            ) {
                viewModel.revealCodexDirectory()
            }

            pathRow(
                label: preferences.string("settings.storage.accountsDirectory"),
                value: viewModel.paths.accountsDirectory.path
            ) {
                viewModel.revealAccountsDirectory()
            }

            pathRow(
                label: preferences.string("settings.storage.metadataFile"),
                value: viewModel.metadataURL.path
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([viewModel.metadataURL])
            }

            Text(preferences.string("settings.storage.note"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text(preferences.string("settings.storage.section"))
        }
    }

    private var actionsSection: some View {
        Section {
            Button(preferences.string("settings.actions.refresh")) {
                viewModel.refresh()
            }

            Button(preferences.string("settings.actions.importSession")) {
                viewModel.importCurrentSession()
            }
            .disabled(!viewModel.liveSessionNeedsImport && !FileManager.default.fileExists(atPath: viewModel.paths.activeAuthFile.path))
        } header: {
            Text(preferences.string("settings.actions.section"))
        }
    }

    private func pathRow(
        label: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button(preferences.string("settings.storage.reveal"), action: action)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
