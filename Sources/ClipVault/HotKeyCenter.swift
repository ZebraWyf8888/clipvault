import AppKit
import Carbon.HIToolbox

/// 全局热键预设。用 Carbon RegisterEventHotKey 实现——不需要辅助功能权限，
/// 这是「不弹权限窗」的关键（CGEventTap 方案需要授权）。
enum HotkeyPreset: String, CaseIterable, Identifiable {
    case ctrlShiftV
    case cmdShiftV
    case optCmdV
    case ctrlCmdV

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ctrlShiftV: return "⌃⇧V"
        case .cmdShiftV: return "⇧⌘V"
        case .optCmdV: return "⌥⌘V"
        case .ctrlCmdV: return "⌃⌘V"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .ctrlShiftV: return UInt32(controlKey | shiftKey)
        case .cmdShiftV: return UInt32(cmdKey | shiftKey)
        case .optCmdV: return UInt32(optionKey | cmdKey)
        case .ctrlCmdV: return UInt32(controlKey | cmdKey)
        }
    }
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var installed = false

    private init() {}

    func setHotkey(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installIfNeeded()
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        self.handler = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: 0x4356_4C54, id: 1) // 'CVLT'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("ClipVault: 热键注册失败（可能被其他应用占用），status=\(status)")
        }
    }

    fileprivate func fire() {
        handler?()
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            HotKeyCenter.shared.fire()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
