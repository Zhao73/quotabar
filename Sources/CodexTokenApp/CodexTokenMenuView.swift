import Charts
import CodexTokenCore
import SwiftUI

struct CodexTokenMenuView: View {
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(spacing: 10) {
            tabBar

            if let notice = viewModel.notice {
                NoticeView(notice: notice, preferences: preferences) { action in
                    viewModel.handleNoticeAction(action)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.notice)
            }

            content
                .frame(maxHeight: 660, alignment: .top)

            footerBar
        }
        .padding(12)
        .frame(width: 520)
        .background(MenuPalette.canvas)
        .onAppear {
            viewModel.menuDidAppear()
            viewModel.ensureSelectedAccountIfNeeded()
        }
        .onDisappear {
            viewModel.menuDidDisappear()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            PremiumTabButton(
                title: preferences.string("tab.overview"),
                tint: MenuPalette.overviewTint,
                isSelected: viewModel.selectedTab == .overview
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    viewModel.selectedTab = .overview
                }
            }

            PremiumTabButton(
                title: "Codex",
                tint: MenuPalette.codexTint,
                isSelected: viewModel.selectedTab == .codex
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    viewModel.selectedTab = .codex
                }
            }

            PremiumTabButton(
                title: preferences.string("tab.claude"),
                tint: MenuPalette.claudeTint,
                isSelected: viewModel.selectedTab == .claude
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    viewModel.selectedTab = .claude
                }
            }

            PremiumTabButton(
                title: preferences.string("tab.antigravity"),
                tint: MenuPalette.antigravityTint,
                isSelected: viewModel.selectedTab == .antigravity
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    viewModel.selectedTab = .antigravity
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .overview:
            OverviewPanelView(viewModel: viewModel, preferences: preferences)
        case .codex:
            CodexWorkspaceView(
                viewModel: viewModel,
                preferences: preferences,
                openSettings: viewModel.openSettings
            )
        case .claude:
            ProviderWorkspaceView(
                summary: viewModel.providerSummary(for: .claude),
                provider: .claude,
                viewModel: viewModel,
                preferences: preferences,
                openSettings: viewModel.openSettings
            )
        case .antigravity:
            AntigravityWorkspaceView(
                summary: viewModel.providerSummary(for: .antigravity),
                viewModel: viewModel,
                preferences: preferences,
                openSettings: viewModel.openSettings
            )
        }
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            FooterButton(title: preferences.string("menu.settings"), systemImage: "gearshape") {
                viewModel.openSettings()
            }

            FooterButton(title: preferences.string("menu.about"), systemImage: "info.circle") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            FooterButton(title: preferences.string("menu.quit"), systemImage: "power") {
                viewModel.quit()
            }
        }
    }
}

private struct OverviewPanelView: View {
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                PremiumCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preferences.string("app.name"))
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(MenuPalette.textPrimary)

                        Text(preferences.string("menu.subtitle"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(MenuPalette.textSecondary)

                        if let lastUpdated = viewModel.relativeLastUpdatedText() {
                            Text(lastUpdated)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(MenuPalette.textMuted)
                        }
                    }
                }

                ForEach(viewModel.overviewSummaries) { summary in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            switch summary.provider {
                            case .codex:
                                viewModel.selectedTab = .codex
                            case .claude:
                                viewModel.selectedTab = .claude
                            case .antigravity:
                                viewModel.selectedTab = .antigravity
                            }
                        }
                    } label: {
                        ProviderSummaryCard(summary: summary, viewModel: viewModel, preferences: preferences)
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.accountRows.isEmpty {
                    PremiumCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: preferences.string("overview.codexAccounts"), eyebrow: "Codex")

                            ForEach(Array(viewModel.accountRows.enumerated()), id: \.element.id) { index, row in
                                Button {
                                    viewModel.showAccount(at: index)
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(row.account.displayName)
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundStyle(MenuPalette.textPrimary)
                                                .lineLimit(1)

                                            Text(row.account.email ?? row.account.accountID ?? preferences.string("menu.account.identifierMissing"))
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundStyle(MenuPalette.textSecondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        if viewModel.isTokenExpired(for: row.quota) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.red)
                                        }
                                        TinyQuotaPill(title: preferences.string("quota.window.5h"), remaining: remainingPercent(for: row.quota.primaryWindow))
                                        TinyQuotaPill(title: preferences.string("quota.window.weekly"), remaining: remainingPercent(for: row.quota.secondaryWindow))
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func remainingPercent(for window: QuotaWindowSnapshot?) -> Int? {
        guard let window else { return nil }
        return max(0, 100 - window.usedPercent)
    }
}

private struct CodexWorkspaceView: View {
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    let openSettings: () -> Void
    @State private var showAccountPicker = false
    @State private var showRemarkEditor = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if let summary = viewModel.codexSummary, let row = viewModel.displayedCodexRow {
                    PremiumHeroCard(tint: MenuPalette.codexTint) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.title)
                                        .font(.system(size: 30, weight: .semibold, design: .serif))
                                        .italic()
                                        .foregroundStyle(MenuPalette.textPrimary)

                                    Text(viewModel.relativeText(for: summary.snapshot.refreshedAt) ?? preferences.string("menu.subtitle"))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(MenuPalette.textSecondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    Button {
                                        showAccountPicker.toggle()
                                    } label: {
                                        HStack(spacing: 6) {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(summary.accountLabel ?? row.account.displayName)
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                    .foregroundStyle(MenuPalette.textPrimary)
                                                    .lineLimit(1)
                                                Text(summary.planLabel ?? preferences.string("menu.account.currentCLI"))
                                                    .font(.system(size: 10.5, weight: .medium))
                                                    .foregroundStyle(MenuPalette.textSecondary)
                                                    .lineLimit(1)
                                            }

                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(MenuPalette.textSecondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(MenuPalette.pillFill, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showAccountPicker, arrowEdge: .top) {
                                        AccountPickerPopover(viewModel: viewModel, preferences: preferences, close: {
                                            showAccountPicker = false
                                        })
                                    }

                                    Button {
                                        showRemarkEditor = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: normalizedRemark(for: row.account) == nil ? "square.and.pencil" : "pencil")
                                                .font(.system(size: 10.5, weight: .semibold))
                                            Text(normalizedRemark(for: row.account) ?? preferences.string("menu.account.addRemark"))
                                                .font(.system(size: 10.5, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(normalizedRemark(for: row.account) == nil ? MenuPalette.textSecondary : MenuPalette.textPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(MenuPalette.softCard, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showRemarkEditor, arrowEdge: .top) {
                                        AccountRemarkPopover(account: row.account, viewModel: viewModel, preferences: preferences) {
                                            showRemarkEditor = false
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 6) {
                                if viewModel.isTokenExpired(for: row.quota) {
                                    StatusBadge(
                                        text: preferences.string("message.needsRelogin"),
                                        tint: .red
                                    )
                                } else {
                                    StatusBadge(
                                        text: statusBadgeTitle(for: row),
                                        tint: viewModel.isSwitchingAccount(storageKey: row.account.storageKey)
                                            ? MenuPalette.antigravityTint
                                            : MenuPalette.codexTint
                                    )
                                }
                                if row.account.isImportedFromActiveSession {
                                    StatusBadge(text: preferences.string("menu.account.currentSession"), tint: MenuPalette.claudeTint)
                                }
                                if let planLabel = summary.planLabel {
                                    StatusBadge(text: planLabel, tint: MenuPalette.antigravityTint)
                                }
                            }
                        }
                    }

                    PremiumCard {
                        HStack(spacing: 12) {
                            AccountDetailItem(
                                label: preferences.string("meta.label.authMode"),
                                value: viewModel.localizedAuthMode(row.account.authMode)
                            )
                            Divider().frame(height: 28)
                            AccountDetailItem(
                                label: preferences.string("meta.label.email"),
                                value: row.account.email ?? "—"
                            )
                            Divider().frame(height: 28)
                            AccountDetailItem(
                                label: preferences.string("meta.label.provider"),
                                value: row.account.loginProvider ?? "—"
                            )
                        }
                    }

                    WindowMetricCard(
                        title: summary.primaryTitle,
                        window: summary.snapshot.primaryWindow,
                        tint: MenuPalette.codexTint,
                        viewModel: viewModel,
                        preferences: preferences,
                        fallbackText: viewModel.localizedQuotaStatus(summary.snapshot.status)
                    )

                    WindowMetricCard(
                        title: summary.secondaryTitle ?? preferences.string("section.weekly"),
                        window: summary.snapshot.secondaryWindow,
                        tint: MenuPalette.tealTint,
                        viewModel: viewModel,
                        preferences: preferences,
                        fallbackText: viewModel.localizedQuotaStatus(summary.snapshot.status)
                    )

                    PremiumCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: preferences.string("section.actions"), eyebrow: "Codex")

                            if viewModel.isTokenExpired(for: row.quota) {
                                ActionChip(title: preferences.string("menu.relogin"), systemImage: "person.badge.key", tint: .red) {
                                    viewModel.reloginCurrentCLI()
                                }
                            }

                            HStack(spacing: 8) {
                                ActionChip(title: preferences.string("menu.switchAccount"), systemImage: "arrow.left.arrow.right", tint: MenuPalette.codexTint) {
                                    viewModel.cycleAccount()
                                }

                                ActionChip(
                                    title: preferences.string("menu.account.openCLI"),
                                    systemImage: "terminal",
                                    tint: MenuPalette.textPrimary,
                                    isNeutral: true
                                ) {
                                    viewModel.openSelectedCLI()
                                }
                            }

                            HStack(spacing: 8) {
                                ActionChip(title: preferences.string("settings.actions.importSession"), systemImage: "square.and.arrow.down", tint: MenuPalette.claudeTint) {
                                    viewModel.importCurrentSession()
                                }

                                if !viewModel.isTokenExpired(for: row.quota) {
                                    ActionChip(title: preferences.string("menu.relogin"), systemImage: "person.badge.key", tint: MenuPalette.overviewTint) {
                                        viewModel.reloginCurrentCLI()
                                    }
                                }

                                ActionChip(title: preferences.string("menu.refresh"), systemImage: "arrow.clockwise", tint: MenuPalette.antigravityTint) {
                                    viewModel.refresh()
                                }
                            }

                            HStack(spacing: 8) {
                                ActionChip(title: preferences.string("menu.copyEmail"), systemImage: "doc.on.doc", tint: MenuPalette.tealTint) {
                                    viewModel.copyAccountEmail()
                                }

                                ActionChip(title: preferences.string("menu.copyQuota"), systemImage: "chart.bar.doc.horizontal", tint: MenuPalette.tealTint) {
                                    viewModel.copyQuotaSummary()
                                }
                            }

                        }
                    }

                    UtilizationCard(
                        title: preferences.string("section.utilization"),
                        subtitle: preferences.string("section.utilization.codexSubtitle"),
                        points: viewModel.selectedChartPoints,
                        tint: MenuPalette.codexTint,
                        summaryFormat: preferences.string("utilization.summary")
                    )
                } else {
                    EmptyProviderState(
                        title: preferences.string("menu.noAccounts"),
                        detail: preferences.string("menu.noAccounts.help")
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func statusBadgeTitle(for row: CodexTokenMenuViewModel.AccountRow) -> String {
        if viewModel.isSwitchingAccount(storageKey: row.account.storageKey) {
            return preferences.string("menu.account.switching")
        }
        return viewModel.isEffectivelyActiveCLI(storageKey: row.account.storageKey)
            ? preferences.string("menu.account.activeCLI")
            : preferences.string("menu.account.savedSnapshot")
    }

    private func normalizedRemark(for account: CodexAccount) -> String? {
        guard let trimmed = account.remark?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct AntigravityWorkspaceView: View {
    let summary: ProviderSurfaceSummary?
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    let openSettings: () -> Void

    private var detailedSnapshot: AntigravityModelsSnapshot? {
        viewModel.antigravityModelsSnapshot
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    AntigravityCreditsCard(
                        snapshot: detailedSnapshot,
                        viewModel: viewModel,
                        preferences: preferences
                    )

                    if viewModel.antigravityModelQuotas.isEmpty {
                        WindowMetricCard(
                            title: summary.primaryTitle,
                            window: summary.snapshot.primaryWindow,
                            tint: MenuPalette.antigravityTint,
                            viewModel: viewModel,
                            preferences: preferences,
                            fallbackText: viewModel.localizedQuotaStatus(summary.snapshot.status)
                        )

                        if let secondaryTitle = summary.secondaryTitle {
                            WindowMetricCard(
                                title: secondaryTitle,
                                window: summary.snapshot.secondaryWindow,
                                tint: MenuPalette.tealTint,
                                viewModel: viewModel,
                                preferences: preferences,
                                fallbackText: viewModel.localizedQuotaStatus(summary.snapshot.status)
                            )
                        }
                    } else {
                        AntigravityQuotaListCard(
                            models: viewModel.antigravityModelQuotas,
                            viewModel: viewModel,
                            preferences: preferences
                        )
                    }

                    AntigravityStatusSummaryCard(
                        summary: summary,
                        snapshot: detailedSnapshot,
                        viewModel: viewModel
                    )

                    PremiumCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: preferences.string("section.actions"), eyebrow: summary.title)

                            HStack(spacing: 8) {
                                ActionChip(title: preferences.string("menu.refresh"), systemImage: "arrow.clockwise", tint: MenuPalette.antigravityTint) {
                                    viewModel.refresh()
                                }
                            }
                        }
                    }

                    UtilizationCard(
                        title: preferences.string("section.utilization"),
                        subtitle: preferences.string("section.utilization.antigravitySubtitle"),
                        points: viewModel.selectedChartPoints,
                        tint: MenuPalette.antigravityTint,
                        summaryFormat: preferences.string("utilization.summary")
                    )
                } else {
                    EmptyProviderState(
                        title: preferences.string("provider.antigravity.unavailableTitle"),
                        detail: preferences.string("provider.antigravity.unavailableBody")
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ProviderWorkspaceView: View {
    let summary: ProviderSurfaceSummary?
    let provider: ProviderKind
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    let openSettings: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    PremiumHeroCard(tint: tint) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.title)
                                        .font(.system(size: 30, weight: .semibold, design: .serif))
                                        .italic()
                                        .foregroundStyle(MenuPalette.textPrimary)

                                    Text(viewModel.relativeText(for: summary.snapshot.refreshedAt) ?? summary.snapshot.sourceLabel)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(MenuPalette.textSecondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    if let accountLabel = summary.accountLabel {
                                        Text(accountLabel)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(MenuPalette.textPrimary)
                                    }
                                    Text(summary.planLabel ?? summary.snapshot.sourceLabel)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(MenuPalette.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(MenuPalette.pillFill, in: Capsule())
                            }

                            StatusBadge(text: viewModel.localizedQuotaStatus(summary.snapshot.status), tint: tint)
                        }
                    }

                    WindowMetricCard(
                        title: summary.primaryTitle,
                        window: summary.snapshot.primaryWindow,
                        tint: tint,
                        viewModel: viewModel,
                        preferences: preferences,
                        fallbackText: viewModel.localizedQuotaStatus(summary.snapshot.status)
                    )

                    if let secondaryTitle = summary.secondaryTitle {
                        WindowMetricCard(
                            title: secondaryTitle,
                            window: summary.snapshot.secondaryWindow,
                            tint: MenuPalette.tealTint,
                            viewModel: viewModel,
                            preferences: preferences,
                            fallbackText: viewModel.localizedQuotaStatus(summary.snapshot.status)
                        )
                    }

                    PremiumCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: preferences.string("section.actions"), eyebrow: summary.title)

                            HStack(spacing: 8) {
                                ActionChip(title: preferences.string("menu.refresh"), systemImage: "arrow.clockwise", tint: tint) {
                                    viewModel.refresh()
                                }
                            }
                        }
                    }

                    UtilizationCard(
                        title: preferences.string("section.utilization"),
                        subtitle: provider == .claude ? preferences.string("section.utilization.claudeSubtitle") : preferences.string("section.utilization.antigravitySubtitle"),
                        points: viewModel.selectedChartPoints,
                        tint: tint,
                        summaryFormat: preferences.string("utilization.summary")
                    )
                } else {
                    EmptyProviderState(
                        title: provider == .claude ? preferences.string("provider.claude.unavailableTitle") : preferences.string("provider.antigravity.unavailableTitle"),
                        detail: provider == .claude ? preferences.string("provider.claude.unavailableBody") : preferences.string("provider.antigravity.unavailableBody")
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var tint: Color {
        switch provider {
        case .codex:
            return MenuPalette.codexTint
        case .claude:
            return MenuPalette.claudeTint
        case .antigravity:
            return MenuPalette.antigravityTint
        }
    }
}

private struct AntigravityCreditsCard: View {
    let snapshot: AntigravityModelsSnapshot?
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences

    var body: some View {
        PremiumCard(fill: MenuPalette.antigravitySurface, stroke: MenuPalette.antigravityStroke, cornerRadius: 16, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: preferences.string("settings.models.credits.section"), eyebrow: "Antigravity")

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preferences.string("settings.models.overage.title"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MenuPalette.textPrimary)
                        Text(preferences.string("settings.models.overage.description"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MenuPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Toggle("", isOn: .constant(snapshot?.overageState == .enabled))
                            .labelsHidden()
                            .disabled(true)
                        Text(overageText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MenuPalette.textSecondary)
                    }
                }

                if let credits = snapshot?.credits {
                    HStack(spacing: 8) {
                        CompactMetricBadge(
                            title: preferences.string("settings.models.credits.prompt"),
                            value: viewModel.formattedCreditBalance(
                                available: credits.availablePromptCredits,
                                total: credits.monthlyPromptCredits
                            )
                        )

                        CompactMetricBadge(
                            title: preferences.string("settings.models.credits.flow"),
                            value: viewModel.formattedCreditBalance(
                                available: credits.availableFlowCredits,
                                total: credits.monthlyFlowCredits
                            )
                        )

                        CompactMetricBadge(
                            title: preferences.string("settings.models.credits.purchase"),
                            value: purchaseText(for: credits)
                        )
                    }
                }
            }
        }
    }

    private var overageText: String {
        switch snapshot?.overageState ?? .unknown {
        case .enabled:
            return preferences.string("settings.models.overage.enabled")
        case .disabled:
            return preferences.string("settings.models.overage.disabled")
        case .unknown:
            return preferences.string("settings.models.overage.unknown")
        }
    }

    private func purchaseText(for credits: AntigravityModelsSnapshot.Credits) -> String {
        if let amount = credits.monthlyFlexCreditPurchaseAmount {
            return amount.formatted()
        }
        if let canBuy = credits.canBuyMoreCredits {
            return canBuy ? preferences.string("settings.models.credits.purchaseAvailable") : preferences.string("settings.models.credits.purchaseUnavailable")
        }
        return preferences.string("quota.value.unknown")
    }
}

private struct AntigravityQuotaListCard: View {
    let models: [AntigravityModelsSnapshot.ModelQuota]
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences

    var body: some View {
        PremiumCard(fill: MenuPalette.antigravitySurface, stroke: MenuPalette.antigravityStroke, cornerRadius: 16, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: preferences.string("settings.models.quota.section"), eyebrow: "Antigravity")

                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(model.label)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(MenuPalette.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(viewModel.detailedResetCountdownText(for: model.resetDate).map { String(format: preferences.string("settings.models.quota.refreshesIn"), $0) } ?? preferences.string("settings.models.quota.noReset"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(MenuPalette.textSecondary)
                        }

                        SegmentedMiniQuotaTrack(remainingPercent: model.remainingPercent, tint: MenuPalette.antigravityTint)
                    }

                    if index < models.count - 1 {
                        Divider()
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct AntigravityStatusSummaryCard: View {
    let summary: ProviderSurfaceSummary
    let snapshot: AntigravityModelsSnapshot?
    @ObservedObject var viewModel: CodexTokenMenuViewModel

    var body: some View {
        PremiumCard(fill: MenuPalette.antigravitySurface, stroke: MenuPalette.antigravityStroke, cornerRadius: 16, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(MenuPalette.textPrimary)

                        if let metadataLine {
                            Text(metadataLine)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(MenuPalette.textSecondary)
                        }
                    }

                    Spacer()

                    StatusBadge(text: viewModel.localizedQuotaStatus(summary.snapshot.status), tint: MenuPalette.antigravityTint)
                }
            }
        }
    }

    private var metadataLine: String? {
        var parts: [String] = []
        if let account = snapshot?.accountEmail ?? snapshot?.accountName ?? summary.accountLabel {
            parts.append(account)
        }
        if let plan = snapshot?.planName ?? summary.planLabel {
            parts.append(plan)
        }
        if let updated = viewModel.relativeText(for: summary.snapshot.refreshedAt) {
            parts.append(updated)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

private struct ProviderSummaryCard: View {
    let summary: ProviderSurfaceSummary
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title)
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(MenuPalette.textPrimary)

                        Text(summary.accountLabel ?? summary.snapshot.sourceLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(MenuPalette.textSecondary)
                    }

                    Spacer()

                    if let planLabel = summary.planLabel {
                        StatusBadge(text: planLabel, tint: tint)
                    }
                }

                MiniQuotaLine(title: summary.primaryTitle, window: summary.snapshot.primaryWindow, tint: tint, preferences: preferences)

                if let secondaryTitle = summary.secondaryTitle {
                    MiniQuotaLine(title: secondaryTitle, window: summary.snapshot.secondaryWindow, tint: MenuPalette.tealTint, preferences: preferences)
                }
            }
        }
    }

    private var tint: Color {
        switch summary.provider {
        case .codex:
            return MenuPalette.codexTint
        case .claude:
            return MenuPalette.claudeTint
        case .antigravity:
            return MenuPalette.antigravityTint
        }
    }
}

private struct AccountPickerPopover: View {
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(preferences.string("menu.switchAccount"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MenuPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ForEach(viewModel.accountRows) { row in
                Button {
                    if viewModel.activateAccount(storageKey: row.account.storageKey) {
                        close()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(row.account.displayName)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(MenuPalette.textPrimary)
                                        .lineLimit(1)
                                    if let remark = normalizedRemark(for: row.account) {
                                        Text("· \(remark)")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(MenuPalette.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Text(row.account.email ?? row.account.accountID ?? preferences.string("menu.account.identifierMissing"))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(MenuPalette.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if viewModel.isSwitchingAccount(storageKey: row.account.storageKey) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(MenuPalette.codexTint)
                            } else if viewModel.isDisplayedCodexAccount(storageKey: row.account.storageKey) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(MenuPalette.codexTint)
                            }
                        }

                        HStack(spacing: 6) {
                            if viewModel.isTokenExpired(for: row.quota) {
                                StatusBadge(
                                    text: preferences.string("message.needsRelogin"),
                                    tint: .red
                                )
                            } else {
                                TinyQuotaPill(title: preferences.string("quota.window.5h"), remaining: remainingPercent(for: row.quota.primaryWindow))
                                TinyQuotaPill(title: preferences.string("quota.window.weekly"), remaining: remainingPercent(for: row.quota.secondaryWindow))
                            }
                            if viewModel.isEffectivelyActiveCLI(storageKey: row.account.storageKey) {
                                StatusBadge(
                                    text: preferences.string("menu.account.activeCLI"),
                                    tint: MenuPalette.codexTint
                                )
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MenuPalette.softCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.isDisplayedCodexAccount(storageKey: row.account.storageKey)
                    || viewModel.switchingAccountStorageKey != nil
                )
            }
        }
        .padding(8)
        .frame(width: 300)
        .background(MenuPalette.canvas)
    }

    private func remainingPercent(for window: QuotaWindowSnapshot?) -> Int? {
        guard let window else { return nil }
        return max(0, 100 - window.usedPercent)
    }

    private func normalizedRemark(for account: CodexAccount) -> String? {
        guard let trimmed = account.remark?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct AccountRemarkPopover: View {
    let account: CodexAccount
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    let close: () -> Void

    @State private var draft: String

    init(
        account: CodexAccount,
        viewModel: CodexTokenMenuViewModel,
        preferences: AppPreferences,
        close: @escaping () -> Void
    ) {
        self.account = account
        self.viewModel = viewModel
        self.preferences = preferences
        self.close = close
        _draft = State(initialValue: account.remark ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preferences.string("menu.account.saveRemark"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MenuPalette.textPrimary)

            TextField(preferences.string("menu.account.remarkPlaceholder"), text: $draft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(preferences.string("menu.account.saveShort")) {
                    viewModel.saveRemark(draft, for: account)
                    close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(MenuPalette.canvas)
    }
}

private struct WindowMetricCard: View {
    let title: String
    let window: QuotaWindowSnapshot?
    let tint: Color
    @ObservedObject var viewModel: CodexTokenMenuViewModel
    let preferences: AppPreferences
    let fallbackText: String

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, eyebrow: nil)

                if let window {
                    QuotaTrack(window: window, tint: tint)

                    HStack(alignment: .lastTextBaseline) {
                        Text(String(format: preferences.string("quota.left"), max(0, 100 - window.usedPercent)))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(MenuPalette.textPrimary)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            if let countdown = viewModel.resetCountdownText(for: window) {
                                Text(countdown)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MenuPalette.textSecondary)
                            }

                            Text(preferences.string("quota.lastsUntilReset"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(MenuPalette.textMuted)
                        }
                    }
                } else {
                    Text(fallbackText)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(MenuPalette.textSecondary)
                }
            }
        }
    }
}

private struct UtilizationCard: View {
    let title: String
    let subtitle: String
    let points: [ProviderChartPoint]
    let tint: Color
    let summaryFormat: String

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, eyebrow: subtitle)

                if points.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MenuPalette.textSecondary)
                } else {
                    Chart(points) { point in
                        BarMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Used", point.usedPercent)
                        )
                        .foregroundStyle(tint.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 108)

                    if let latest = points.last {
                        Text(String(format: summaryFormat, latest.usedPercent))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MenuPalette.textSecondary)
                    }
                }
            }
        }
    }
}

private struct PremiumHeroCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        PremiumCard(fill: MenuPalette.heroCard, stroke: tint.opacity(0.18)) {
            content
        }
    }
}

private struct PremiumCard<Content: View>: View {
    var fill: Color = MenuPalette.softCard
    var stroke: Color = MenuPalette.stroke
    var cornerRadius: CGFloat = 20
    var shadowOpacity: Double = 0.03
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 4
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: 0.8)
                )
        )
        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }
}

private struct PremiumTabButton: View {
    let title: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : MenuPalette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? tint : MenuPalette.tabFill)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(MenuPalette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MenuPalette.softCard, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    let title: String
    let eyebrow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(MenuPalette.textPrimary)
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MenuPalette.textMuted)
            }
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private struct ActionChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isNeutral = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(isNeutral ? tint : Color.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background((isNeutral ? MenuPalette.pillFill : tint).opacity(isHovered ? 0.85 : 1.0), in: Capsule())
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct TinyQuotaPill: View {
    let title: String
    let remaining: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
            Text(remaining.map { "\($0)%" } ?? "--")
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(MenuPalette.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(MenuPalette.pillFill, in: Capsule())
    }
}

private struct AccountDetailItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(MenuPalette.textMuted)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(MenuPalette.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactMetricBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(MenuPalette.textMuted)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(MenuPalette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MenuPalette.pillFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MiniQuotaLine: View {
    let title: String
    let window: QuotaWindowSnapshot?
    let tint: Color
    let preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(MenuPalette.textSecondary)
                Spacer()
                Text(window.map { String(format: preferences.string("quota.left"), max(0, 100 - $0.usedPercent)) } ?? "--")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MenuPalette.textMuted)
            }

            QuotaTrack(window: window, tint: tint)
        }
    }
}

private struct QuotaTrack: View {
    let window: QuotaWindowSnapshot?
    let tint: Color

    private var effectiveTint: Color {
        guard let window else { return tint }
        let remaining = 100 - window.usedPercent
        if remaining <= 10 { return .red }
        if remaining <= 25 { return .orange }
        return tint
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuPalette.track)
                if let window {
                    let remaining = CGFloat(max(0, 100 - window.usedPercent)) / 100
                    Capsule()
                        .fill(effectiveTint.gradient)
                        .frame(width: max(16, proxy.size.width * remaining))
                        .animation(.easeInOut(duration: 0.4), value: window.usedPercent)
                }
            }
        }
        .frame(height: 8)
    }
}

private struct SegmentedMiniQuotaTrack: View {
    let remainingPercent: Int
    let tint: Color

    private var filledSegments: Int {
        if remainingPercent <= 0 { return 0 }
        return min(5, max(1, Int(ceil(Double(remainingPercent) / 20.0))))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index < filledSegments ? tint : MenuPalette.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: 6)
            }
        }
    }
}

private struct EmptyProviderState: View {
    let title: String
    let detail: String

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(MenuPalette.textPrimary)

                Text(detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(MenuPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }
}

private struct NoticeView: View {
    let notice: CodexTokenMenuViewModel.Notice
    let preferences: AppPreferences
    let actionHandler: (CodexTokenMenuViewModel.Notice.Action) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if notice.tone == .error || notice.tone == .warning {
                Image(systemName: notice.tone == .error ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foreground)
            }

            Text(notice.text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let action = notice.action {
                Button(actionTitle(for: action)) {
                    actionHandler(action)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(notice.tone == .error ? Color.white : foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    notice.tone == .error
                        ? AnyShapeStyle(foreground)
                        : AnyShapeStyle(Color.white.opacity(0.45)),
                    in: Capsule()
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var foreground: Color {
        switch notice.tone {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }

    private func actionTitle(for action: CodexTokenMenuViewModel.Notice.Action) -> String {
        switch action {
        case .reloginCurrentCLI:
            return preferences.string("menu.relogin")
        case .refreshNow:
            return preferences.string("menu.refresh")
        case .openSettings:
            return preferences.string("menu.settings")
        }
    }
}

private enum MenuPalette {
    static let canvas = Color.clear
    static let softCard = adaptive(light: NSColor.white.withAlphaComponent(0.55), dark: NSColor.white.withAlphaComponent(0.06))
    static let heroCard = adaptive(light: NSColor.white.withAlphaComponent(0.65), dark: NSColor.white.withAlphaComponent(0.08))
    static let tabFill = adaptive(light: NSColor.black.withAlphaComponent(0.04), dark: NSColor.white.withAlphaComponent(0.06))
    static let pillFill = adaptive(light: NSColor.black.withAlphaComponent(0.04), dark: NSColor.white.withAlphaComponent(0.08))
    static let track = adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.10))
    static let stroke = adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.12))
    static let textPrimary = adaptive(light: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1), dark: NSColor(calibratedWhite: 0.97, alpha: 1))
    static let textSecondary = adaptive(light: NSColor(calibratedRed: 0.35, green: 0.38, blue: 0.43, alpha: 1), dark: NSColor(calibratedWhite: 0.75, alpha: 1))
    static let textMuted = adaptive(light: NSColor(calibratedRed: 0.52, green: 0.55, blue: 0.60, alpha: 1), dark: NSColor(calibratedWhite: 0.55, alpha: 1))
    static let overviewTint = Color(nsColor: .darkGray)
    static let codexTint = Color(nsColor: NSColor(calibratedRed: 0.17, green: 0.43, blue: 1.0, alpha: 1))
    static let claudeTint = Color(nsColor: NSColor(calibratedRed: 0.87, green: 0.49, blue: 0.29, alpha: 1))
    static let antigravityTint = Color(nsColor: NSColor(calibratedRed: 0.55, green: 0.41, blue: 0.94, alpha: 1))
    static let antigravitySurface = adaptive(light: NSColor.white.withAlphaComponent(0.45), dark: NSColor.white.withAlphaComponent(0.04))
    static let antigravityStroke = adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.10))
    static let tealTint = Color(nsColor: NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.55, alpha: 1))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return match == .darkAqua ? dark : light
            }
        )
    }
}
