import CodexTokenCore
import SwiftUI

struct CodexTokenMenuView: View {
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    @ObservedObject var preferences: AppPreferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header

            if let notice = viewModel.notice {
                NoticeView(notice: notice)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider()

            content
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxHeight: 520, alignment: .top)
        }
        .frame(width: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.menuDidAppear()
        }
        .onDisappear {
            viewModel.menuDidDisappear()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preferences.string("app.name"))
                    .font(.headline.weight(.semibold))

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let lastUpdated = viewModel.relativeLastUpdatedText() {
                    Text(lastUpdated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.refresh()
            } label: {
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help(preferences.string("menu.refresh"))

            Menu {
                Button(preferences.string("menu.settings")) {
                    openSettings()
                }
                Divider()
                Button(preferences.string("menu.quit")) {
                    viewModel.quit()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.accountRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(preferences.string("menu.noAccounts"))
                    .font(.headline)
                Text(preferences.string("menu.noAccounts.help"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        } else {
            ScrollView(.vertical, showsIndicators: viewModel.accountRows.count > 6) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(viewModel.accountRows) { row in
                        AccountCardView(
                            row: row,
                            viewModel: viewModel,
                            preferences: preferences
                        )
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)
        ]
    }

    private var headerSubtitle: String {
        let countText = String(format: preferences.string("menu.header.accountCount"), viewModel.accountRows.count)
        guard let active = viewModel.accountRows.first(where: { $0.account.isActiveCLI }) else {
            return "\(preferences.string("menu.header.noActive")) • \(countText)"
        }
        let current = String(format: preferences.string("menu.header.activeAccount"), active.account.email ?? active.account.displayName)
        return "\(current) • \(countText)"
    }
}

private struct AccountCardView: View {
    let row: CodexTokenMenuViewModel.AccountRow
    let viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    @State private var isEditingRemark = false
    @State private var remarkDraft: String

    init(
        row: CodexTokenMenuViewModel.AccountRow,
        viewModel: CodexTokenMenuViewModel,
        preferences: AppPreferences
    ) {
        self.row = row
        self.viewModel = viewModel
        self.preferences = preferences
        _remarkDraft = State(initialValue: row.account.remark ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    badgeRow
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    primaryActionButton

                    HStack(spacing: 4) {
                        Button {
                            viewModel.moveAccount(storageKey: row.account.storageKey, direction: .up)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!viewModel.canMoveAccount(storageKey: row.account.storageKey, direction: .up))
                        .help(preferences.string("menu.account.moveUp"))

                        Button {
                            viewModel.moveAccount(storageKey: row.account.storageKey, direction: .down)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!viewModel.canMoveAccount(storageKey: row.account.storageKey, direction: .down))
                        .help(preferences.string("menu.account.moveDown"))
                    }
                }
            }

            Button {
                isEditingRemark = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.caption2)
                    Text(remarkButtonText)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(trimmedRemark == nil ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingRemark, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        preferences.string("menu.account.remarkPlaceholder"),
                        text: $remarkDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                    HStack {
                        Spacer()

                        Button(preferences.string("menu.account.saveRemark")) {
                            viewModel.saveRemark(remarkDraft, for: row.account)
                            isEditingRemark = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
            }

            Text(fiveHourQuotaLine)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(weeklyQuotaLine)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(maskedAccountID)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(detailLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let errorDescription = row.quota.errorDescription, !errorDescription.isEmpty {
                Text(errorDescription)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
        .onChange(of: row.account.remark ?? "", initial: false) { _, newValue in
            if newValue != remarkDraft {
                remarkDraft = newValue
            }
        }
    }

    private var displayName: String {
        let candidate = row.account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? preferences.string("menu.account.identifierMissing") : candidate
    }

    private var trimmedRemark: String? {
        guard let remark = row.account.remark?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remark.isEmpty
        else {
            return nil
        }
        return remark
    }

    private var remarkButtonText: String {
        trimmedRemark ?? preferences.string("menu.account.addRemark")
    }

    private var maskedAccountID: String {
        guard let accountID = row.account.accountID, !accountID.isEmpty else {
            return preferences.string("menu.account.identifierMissing")
        }
        guard accountID.count > 14 else { return accountID }
        return "\(accountID.prefix(8))…\(accountID.suffix(4))"
    }

    private var detailLine: String {
        let refreshedAt = row.quota.refreshedAt ?? row.account.lastRefreshAt
        return viewModel.formattedTimestamp(refreshedAt)
    }

    private var needsRelogin: Bool {
        guard let errorDescription = row.quota.errorDescription?.lowercased() else { return false }
        return errorDescription.contains("refresh token") && errorDescription.contains("401")
    }

    private var badgeRow: some View {
        HStack(spacing: 4) {
            if row.account.isActiveCLI {
                statusBadge(preferences.string("menu.account.activeCLI"), tint: .green)
            }

            if row.account.isImportedFromActiveSession {
                statusBadge(preferences.string("menu.account.currentSession"), tint: .orange)
            }

            if isExperimentalQuota {
                statusBadge(preferences.string("quota.status.experimental"), tint: .blue)
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if row.account.isImportedFromActiveSession {
            Button(preferences.string("menu.account.saveShort")) {
                viewModel.importCurrentSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button(preferences.string("menu.account.openCLI")) {
                viewModel.openCLI(for: row.account)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var isExperimentalQuota: Bool {
        row.quota.primaryWindow != nil || row.quota.secondaryWindow != nil
    }

    private var fiveHourQuotaLine: String {
        quotaWindowLine(duration: 300)
    }

    private var weeklyQuotaLine: String {
        quotaWindowLine(duration: 10_080)
    }

    private func quotaWindowLine(duration: Int) -> String {
        let label = duration == 300
            ? preferences.string("quota.window.5h")
            : preferences.string("quota.window.weekly")

        guard let window = quotaWindow(duration: duration) else {
            return "\(label) \(viewModel.localizedQuotaStatus(row.quota.status))"
        }

        let remaining = viewModel.quotaWindowRemainingText(window) ?? "—"
        let reset = viewModel.formattedTimestamp(window.resetsAt)
        return "\(label) \(remaining) • \(preferences.string("quota.resetsAt")) \(reset)"
    }

    private func quotaWindow(duration: Int) -> QuotaWindowSnapshot? {
        let candidates = [row.quota.primaryWindow, row.quota.secondaryWindow].compactMap { $0 }
        if let exact = candidates.first(where: { $0.windowDurationMinutes == duration }) {
            return exact
        }
        switch duration {
        case 300:
            return row.quota.primaryWindow
        case 10_080:
            return row.quota.secondaryWindow
        default:
            return nil
        }
    }

    private var cardFill: Color {
        if row.account.isActiveCLI {
            return Color.accentColor.opacity(0.14)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var cardBorder: Color {
        if row.account.isActiveCLI {
            return .accentColor.opacity(0.35)
        }
        return Color.secondary.opacity(0.12)
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct NoticeView: View {
    let notice: CodexTokenMenuViewModel.Notice

    var body: some View {
        Text(notice.text)
            .font(.caption)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var foregroundColor: Color {
        switch notice.tone {
        case .info:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.10)
    }
}
