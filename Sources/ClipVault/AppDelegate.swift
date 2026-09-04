import AppKit
import Carbon.HIToolbox
import Combine
import ClipVaultCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsStore: AppSettingsStore!
    private var history: HistoryController!
    private var watcher: PasteboardWatcher!
    private var statusItem: StatusItemController!
    private var panelController: PanelController!
    private var settingsWindow: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateIfAlreadyRunning()

        settingsStore = AppSettingsStore()
        history = HistoryController(settings: settingsStore)
        panelController = PanelController(history: history, settings: settingsStore)
        settingsWindow = SettingsWindowController(settings: settingsStore, history: history)

        statusItem = StatusItemController()
        statusItem.onTogglePanel = { [weak self] in self?.panelController.toggle() }
        statusItem.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem.onClearHistory = { [weak self] in self?.confirmClearHistory() }

        watcher = PasteboardWatcher()
        watcher.onCandidate = { [weak self] candidate in
            self?.history.handleCandidate(candidate)
        }
        let pollMS = Int(ProcessInfo.processInfo.environment["CLIPVAULT_POLL_MS"] ?? "") ?? 350
        watcher.start(intervalMS: pollMS)

        applyHotkey(settingsStore.value.hotkey)
        settingsStore.$value
            .map(\.hotkey)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] raw in self?.applyHotkey(raw) }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        history?.saveNow()
    }

    private func applyHotkey(_ raw: String) {
        let preset = HotkeyPreset(rawValue: raw) ?? .ctrlShiftV
        HotKeyCenter.shared.setHotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: preset.carbonModifiers) { [weak self] in
            self?.panelController.toggle()
        }
    }

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴板历史？"
        alert.informativeText = "内存与磁盘上的记录都会被删除，且无法恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            history.clearAll()
        }
    }

    /// 已有实例在跑时直接退出，避免双份轮询和热键冲突。仅对打包后的 .app 生效。
    private func terminateIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID == "com.zebrawyf.clipvault" else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
        }
    }
}
