import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store = MarketStore()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverHostingController: NSHostingController<ContentView>?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private lazy var statusMenu: NSMenu = makeStatusMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePopover()
        bindNotifications()
        bindStore()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "OKX --"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.image = NSImage(
            systemSymbolName: "chart.line.uptrend.xyaxis",
            accessibilityDescription: "OKX"
        )
        item.button?.imagePosition = .imageLeading
        item.button?.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let editMenuItem = NSMenuItem()

        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出 OKXMenuBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "设置", action: #selector(openSettingsWindow), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 520, height: 720)
        popover.behavior = .transient
        popover.delegate = self

        let hostingController = NSHostingController(rootView: ContentView(store: store))
        popover.contentViewController = hostingController

        self.popoverHostingController = hostingController
        self.popover = popover
        resizePopoverToFitContent()
    }

    private func bindNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: .openSettingsWindow,
            object: nil
        )
    }

    private func bindStore() {
        store.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusTitle()
                self?.schedulePopoverResize()
            }
            .store(in: &cancellables)

        store.$positions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.schedulePopoverResize()
            }
            .store(in: &cancellables)

        store.$positionState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.schedulePopoverResize()
            }
            .store(in: &cancellables)
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }

        let snapshots = store.snapshots.filter {
            $0.contract.id == "BTC-USDT-SWAP" || $0.contract.id == "ETH-USDT-SWAP"
        }
        guard !snapshots.isEmpty else {
            button.title = "OKX --"
            return
        }

        let title = NSMutableAttributedString()
        for snapshot in snapshots {
            guard let ticker = snapshot.ticker else { continue }
            if title.length > 0 {
                title.append(NSAttributedString(string: "  "))
            }

            let prefix = snapshot.contract.symbol == "BTC" ? "₿" : "Ξ"
            title.append(statusText("\(prefix) \(NumberFormat.compactPrice(ticker.last)) "))
            title.append(statusText(
                NumberFormat.percent(ticker.change24h),
                color: ticker.change24h >= 0 ? .systemRed : .systemGreen
            ))
        }

        if title.length == 0 {
            button.title = "OKX --"
        } else {
            button.attributedTitle = title
        }
    }

    private func statusText(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color
            ]
        )
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            showStatusMenu()
        default:
            togglePopover(sender)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            resizePopoverToFitContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { [weak self] in
                await self?.store.refreshSelectedContractCandles()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showStatusMenu() {
        popover?.performClose(nil)
        statusItem?.menu = statusMenu
        statusItem?.button?.performClick(nil)
    }

    private func schedulePopoverResize() {
        DispatchQueue.main.async { [weak self] in
            self?.resizePopoverToFitContent()
        }
    }

    private func resizePopoverToFitContent() {
        guard let popover, let hostingController = popoverHostingController else { return }

        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.layoutSubtreeIfNeeded()

        let fittingSize = hostingController.view.fittingSize
        let targetScreenHeight = statusItem?.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900
        let maxHeight = max(640, targetScreenHeight - 120)
        let width = max(520, fittingSize.width)
        let height = min(max(640, fittingSize.height), maxHeight)

        popover.contentSize = NSSize(width: width, height: height)
    }

    @objc private func openSettingsWindow() {
        popover?.performClose(nil)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsView(store: store) { [weak self] in
            self?.settingsWindow?.close()
            self?.settingsWindow = nil
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OKX API 配置"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu {
            statusItem?.menu = nil
        }
    }
}

extension Notification.Name {
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
}

@main
struct OKXMenuBarApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
