import AppKit
import ApplicationServices

enum Paster {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统的辅助功能授权引导（仅在用户主动开启「自动粘贴」时调用）。
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 向当前前台应用注入 ⌘V。
    static func pasteViaCmdV() {
        guard isTrusted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
