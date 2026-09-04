import AppKit
import SwiftUI
import ClipVaultCore

final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let settings: AppSettingsStore
    private let history: HistoryController

    init(settings: AppSettingsStore, history: HistoryController) {
        self.settings = settings
        self.history = history
        super.init()
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "ClipVault 设置"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings, history: history))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    let history: HistoryController

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("通用", systemImage: "gearshape") }
            ContentSettingsTab(settings: settings)
                .tabItem { Label("内容", systemImage: "doc.on.clipboard") }
            SecuritySettingsTab(settings: settings, history: history)
                .tabItem { Label("安全", systemImage: "lock.shield") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 460)
    }
}

// MARK: - 通用

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    @State private var loginItemError = false

    var body: some View {
        Form {
            Picker("历史保留时长", selection: binding(\.retentionHours)) {
                Text("1 小时").tag(1)
                Text("24 小时").tag(24)
                Text("3 天").tag(72)
                Text("7 天").tag(168)
                Text("30 天").tag(720)
                Text("永久").tag(0)
            }

            Picker("最多保留条数", selection: binding(\.maxItems)) {
                Text("100").tag(100)
                Text("300").tag(300)
                Text("500").tag(500)
                Text("1000").tag(1000)
                Text("3000").tag(3000)
            }

            Picker("全局快捷键", selection: binding(\.hotkey)) {
                ForEach(HotkeyPreset.allCases) { preset in
                    Text(preset.label).tag(preset.rawValue)
                }
            }

            Toggle("开机自动启动", isOn: launchAtLoginBinding)
            if loginItemError {
                Text("设置失败：请把 ClipVault.app 放进「应用程序」后再试。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("选中后自动粘贴到当前应用", isOn: autoPasteBinding)
            Text("自动粘贴需要「辅助功能」权限（系统设置 → 隐私与安全性 → 辅助功能）。不开启则选中后只写入剪贴板，自己按 ⌘V。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CVSettings, T>) -> Binding<T> {
        Binding(get: { settings.value[keyPath: keyPath] },
                set: { settings.value[keyPath: keyPath] = $0 })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.value.launchAtLogin },
            set: { on in
                if LoginItem.set(enabled: on) {
                    settings.value.launchAtLogin = on
                    loginItemError = false
                } else {
                    loginItemError = true
                }
            }
        )
    }

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { settings.value.autoPaste },
            set: { on in
                settings.value.autoPaste = on
                if on && !Paster.isTrusted {
                    Paster.requestTrust()
                }
            }
        )
    }
}

// MARK: - 内容

struct ContentSettingsTab: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        Form {
            Toggle("保存图片", isOn: binding(\.keepImages))

            Picker("图片大小上限", selection: binding(\.maxImageBytes)) {
                Text("2 MB").tag(2 * 1024 * 1024)
                Text("5 MB").tag(5 * 1024 * 1024)
                Text("10 MB").tag(10 * 1024 * 1024)
                Text("20 MB").tag(20 * 1024 * 1024)
                Text("50 MB").tag(50 * 1024 * 1024)
            }
            .disabled(!settings.value.keepImages)

            Picker("单条文本大小上限", selection: binding(\.maxTextBytes)) {
                Text("64 KB").tag(64 * 1024)
                Text("256 KB").tag(256 * 1024)
                Text("1 MB").tag(1024 * 1024)
                Text("4 MB").tag(4 * 1024 * 1024)
            }

            Text("超过上限的内容不会进入历史（复制本身不受影响）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CVSettings, T>) -> Binding<T> {
        Binding(get: { settings.value[keyPath: keyPath] },
                set: { settings.value[keyPath: keyPath] = $0 })
    }
}

// MARK: - 安全

struct SecuritySettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    let history: HistoryController
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section("捕获规则") {
                Toggle("跳过密码管理器标记的内容", isOn: binding(\.skipConcealed))
                Text("1Password、Bitwarden 等复制密码时会打 Concealed 标记，开启后这类内容不会进入历史。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("跳过临时 / 自动生成内容", isOn: binding(\.skipTransient))

                Picker("疑似密钥 / Token", selection: binding(\.secretPolicy)) {
                    Text("不记录").tag(SecretPolicy.ignore)
                    Text("记录但遮罩显示").tag(SecretPolicy.mask)
                    Text("不检测").tag(SecretPolicy.off)
                }
                Text("内置 GitHub / AWS / Slack / JWT / 私钥等常见凭证格式检测。「遮罩」= 列表里只显示圆点，仍可复制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("排除应用（这些应用里复制的内容一律不记录）") {
                ExcludedAppsEditor(settings: settings)
            }

            Section("存储") {
                Toggle("历史加密保存到磁盘", isOn: binding(\.persistToDisk))
                Text(settings.value.persistToDisk
                     ? "AES-256-GCM 加密后写入本机（\(HistoryController.dataDirectory.path)），重启不丢。"
                     : "仅保存在内存：退出或重启即全部清空，磁盘上不留任何痕迹。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("立即清空全部历史…", role: .destructive) {
                    confirmingClear = true
                }
                .confirmationDialog("清空全部剪贴板历史？此操作无法恢复。",
                                    isPresented: $confirmingClear) {
                    Button("清空", role: .destructive) { history.clearAll() }
                    Button("取消", role: .cancel) {}
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CVSettings, T>) -> Binding<T> {
        Binding(get: { settings.value[keyPath: keyPath] },
                set: { settings.value[keyPath: keyPath] = $0 })
    }
}

struct ExcludedAppsEditor: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(settings.value.excludedBundleIDs, id: \.self) { bid in
                HStack {
                    Text(bid)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button {
                        settings.value.excludedBundleIDs.removeAll { $0 == bid }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("添加应用…") {
                pickApp()
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK,
           let url = panel.url,
           let bid = Bundle(url: url)?.bundleIdentifier,
           !settings.value.excludedBundleIDs.contains(bid) {
            settings.value.excludedBundleIDs.append(bid)
        }
    }
}

// MARK: - 关于

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("ClipVault")
                .font(.title2.bold())
            Text("版本 0.1.0")
                .foregroundStyle(.secondary)
            Text("安全优先的本地剪贴板历史工具。\n所有数据仅保存在本机并加密落盘，不发起任何网络请求。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Button("在访达中显示数据目录") {
                NSWorkspace.shared.activateFileViewerSelecting([HistoryController.dataDirectory])
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
