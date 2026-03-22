import AppKit
import Combine
import CodexTokenCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let viewModel: CodexTokenMenuViewModel
    private let preferences: AppPreferences
    private var cancellables: Set<AnyCancellable> = []
    private var isPresentingContextMenu = false

    init(viewModel: CodexTokenMenuViewModel, preferences: AppPreferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        super.init()
        bindState()
        installStatusItemIfNeeded()
    }

    @MainActor
    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        guard !isPresentingContextMenu else { return }

        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            presentContextMenu(from: button, event: event)
            return
        }

        togglePopover(sender)
    }

    @MainActor
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func configurePopover() {
        let rootView = CodexTokenMenuView(viewModel: viewModel, preferences: preferences)
        let hostingController = NSHostingController(rootView: rootView)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 760)
        popover.contentViewController = hostingController
        popover.delegate = self
    }

    private func configureStatusItem() {
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = viewModel.menuBarTitle
        updateButtonAppearance()
    }

    private func bindState() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButtonAppearance()
            }
            .store(in: &cancellables)
    }

    private func updateButtonAppearance() {
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(
            systemSymbolName: viewModel.menuBarSymbolName,
            accessibilityDescription: viewModel.menuBarTitle
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.title = "QB"
        button.imagePosition = image == nil ? .imageLeft : .imageLeading
        button.toolTip = viewModel.menuBarTitle
        button.setAccessibilityLabel(viewModel.menuBarTitle)
        button.appearsDisabled = false
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configurePopover()
        configureStatusItem()
    }

    @MainActor
    private func presentContextMenu(from button: NSStatusBarButton, event: NSEvent?) {
        if popover.isShown {
            popover.performClose(button)
        }

        guard let event else { return }
        isPresentingContextMenu = true
        let menu = makeContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: button)
        isPresentingContextMenu = false
    }

    @MainActor
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let openPanel = NSMenuItem(title: preferences.string("menu.openPanel"), action: #selector(openPanelFromContextMenu(_:)), keyEquivalent: "")
        openPanel.target = self
        menu.addItem(openPanel)

        let refreshItem = NSMenuItem(title: preferences.string("menu.refresh"), action: #selector(refreshFromContextMenu(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: preferences.string("menu.settings"), action: #selector(openSettingsFromContextMenu(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let switchAccountItem = NSMenuItem(title: preferences.string("menu.switchAccount"), action: nil, keyEquivalent: "")
        switchAccountItem.submenu = makeAccountSwitchSubmenu()
        menu.addItem(switchAccountItem)

        let reloginItem = NSMenuItem(title: preferences.string("menu.relogin"), action: #selector(reloginFromContextMenu(_:)), keyEquivalent: "")
        reloginItem.target = self
        menu.addItem(reloginItem)

        let openCLIItem = NSMenuItem(title: preferences.string("menu.openCLI"), action: #selector(openCLIFromContextMenu(_:)), keyEquivalent: "")
        openCLIItem.target = self
        openCLIItem.isEnabled = viewModel.selectedAccountRow != nil
        menu.addItem(openCLIItem)

        let importItem = NSMenuItem(title: preferences.string("menu.importSession"), action: #selector(importCurrentSessionFromContextMenu(_:)), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: preferences.string("menu.quit"), action: #selector(quitFromContextMenu(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @MainActor
    private func makeAccountSwitchSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for row in viewModel.accountRows {
            let item = NSMenuItem(
                title: accountMenuTitle(for: row.account),
                action: #selector(switchAccountFromContextMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = row.account.storageKey
            item.state = viewModel.isDisplayedCodexAccount(storageKey: row.account.storageKey) ? .on : .off
            item.isEnabled = viewModel.switchingAccountStorageKey == nil
            submenu.addItem(item)
        }
        return submenu
    }

    private func accountMenuTitle(for account: CodexAccount) -> String {
        let base = account.email ?? account.displayName
        guard let remark = account.remark?.trimmingCharacters(in: .whitespacesAndNewlines), !remark.isEmpty else {
            return base
        }
        return "\(base) · \(remark)"
    }

    @MainActor
    @objc
    private func openPanelFromContextMenu(_ sender: AnyObject?) {
        togglePopover(sender)
    }

    @MainActor
    @objc
    private func refreshFromContextMenu(_ sender: AnyObject?) {
        viewModel.refresh(showSuccessNotice: false)
    }

    @MainActor
    @objc
    private func openSettingsFromContextMenu(_ sender: AnyObject?) {
        viewModel.openSettings()
    }

    @MainActor
    @objc
    private func switchAccountFromContextMenu(_ sender: NSMenuItem) {
        guard let storageKey = sender.representedObject as? String else { return }
        viewModel.activateAccount(storageKey: storageKey)
    }

    @MainActor
    @objc
    private func reloginFromContextMenu(_ sender: AnyObject?) {
        viewModel.reloginCurrentCLI()
    }

    @MainActor
    @objc
    private func openCLIFromContextMenu(_ sender: AnyObject?) {
        viewModel.openSelectedCLI()
    }

    @MainActor
    @objc
    private func importCurrentSessionFromContextMenu(_ sender: AnyObject?) {
        viewModel.importCurrentSession()
    }

    @MainActor
    @objc
    private func quitFromContextMenu(_ sender: AnyObject?) {
        viewModel.quit()
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        viewModel.menuDidAppear()
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.menuDidDisappear()
    }
}
