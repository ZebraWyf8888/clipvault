import Foundation
import Combine
import ClipVaultCore

/// 设置的持久化封装：UserDefaults 存 JSON。
/// 端到端测试可用 CLIPVAULT_SETTINGS_JSON 注入设置（此时不写回 UserDefaults）。
final class AppSettingsStore: ObservableObject {
    @Published var value: CVSettings {
        didSet { persist() }
    }

    private static let defaultsKey = "com.clipvault.settings.v1"
    private let ephemeral: Bool

    init() {
        if let env = ProcessInfo.processInfo.environment["CLIPVAULT_SETTINGS_JSON"],
           let data = env.data(using: .utf8),
           let s = try? JSONDecoder().decode(CVSettings.self, from: data) {
            value = s
            ephemeral = true
            return
        }
        ephemeral = false
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let s = try? JSONDecoder().decode(CVSettings.self, from: data) {
            value = s
        } else {
            value = .default
        }
    }

    private func persist() {
        guard !ephemeral else { return }
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
