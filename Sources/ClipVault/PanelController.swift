import AppKit
import Combine
import SwiftUI
import ClipVaultCore

final class PanelViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { refilter(resetSelection: true) }
    }
    @Published private(set) var filtered: [ClipItem] = []
    @Published var selectedIndex: Int = 0
    /// 每次面板弹出时 +1，驱动搜索框重新聚焦
    @Published var focusTick: Int = 0

    var onConfirm: ((ClipItem) -> Void)?
    var onDeleteRequest: ((ClipItem) -> Void)?

    private let history: HistoryController
    private var cancellables = Set<AnyCancellable>()

    init(history: HistoryController) {
        self.history = history
        history.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refilter(resetSelection: false) }
            .store(in: &cancellables)
        refilter(resetSelection: true)
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard case .image(let meta) = item.kind, let data = meta.thumbnailPNG else { return nil }
        return NSImage(data: data)
    }

    func prepareForShow() {
        query = ""
        selectedIndex = 0
        focusTick += 1
    }

    func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + delta), filtered.count - 1)
    }

    func confirmSelection() {
        confirm(at: selectedIndex)
    }

    func confirm(at index: Int) {
        guard filtered.indices.contains(index) else { return }
        onConfirm?(filtered[index])
    }

    func deleteSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        onDeleteRequest?(filtered[selectedIndex])
    }

    private func refilter(resetSelection: Bool) {
        filtered = historySearch()
        if resetSelection {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, max(0, filtered.count - 1))
        }
    }

    private func historySearch() -> [ClipItem] {
        history.searchItems(query)
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    let viewModel: PanelViewModel
    private let history: HistoryController
    private let settings: AppSettingsStore
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(history: HistoryController, settings: AppSettingsStore) {
        self.history = history
        self.settings = settings
        viewModel = PanelViewModel(history: history)
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440))
        super.init()

        panel.contentView = NSHostingView(rootView: PanelView(model: viewModel))
        panel.delegate = self
        viewModel.onConfirm = { [weak self] item in self?.confirm(item) }
        viewModel.onDeleteRequest = { [weak self] item in self?.history.delete(item) }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.prepareForShow()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            let x = vf.midX - panel.frame.width / 2
            let y = vf.midY - panel.frame.height / 2 + vf.height * 0.08
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func confirm(_ item: ClipItem) {
        let prev = previousApp
        hide()
        history.copyToPasteboard(item)
        prev?.activate()
        if settings.value.autoPaste && Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Paster.pasteViaCmdV()
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            switch event.keyCode {
            case 125: // ↓
                self.viewModel.moveSelection(1)
                return nil
            case 126: // ↑
                self.viewModel.moveSelection(-1)
                return nil
            case 53: // esc
                self.hide()
                return nil
            case 36, 76: // return / enter
                self.viewModel.confirmSelection()
                return nil
            case 51: // delete
                if event.modifierFlags.contains(.command) {
                    self.viewModel.deleteSelection()
                    return nil
                }
                return event
            default:
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), (1...9).contains(n) {
                    self.viewModel.confirm(at: n - 1)
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}

extension HistoryController {
    /// PanelViewModel 的查询入口（保持 HistoryStore 私有）。
    func searchItems(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            if let app = item.sourceAppName, app.localizedCaseInsensitiveContains(q) { return true }
            switch item.kind {
            case .text(let s):
                return !item.isSensitive && s.localizedCaseInsensitiveContains(q)
            case .image:
                return "图片".localizedCaseInsensitiveContains(q) || "image".localizedCaseInsensitiveContains(q)
            }
        }
    }
}
