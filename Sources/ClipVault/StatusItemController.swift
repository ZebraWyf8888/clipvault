import AppKit

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem

    var onTogglePanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onClearHistory: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "ClipVault")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onTogglePanel?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开剪贴板面板", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let clear = NSMenuItem(title: "清空历史…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ClipVault", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        // 临时挂上菜单弹出，弹完摘掉，保证左键仍然直接开面板
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() { onTogglePanel?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func clearHistory() { onClearHistory?() }
}
