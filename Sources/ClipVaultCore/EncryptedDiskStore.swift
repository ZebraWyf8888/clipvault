import Foundation
import CryptoKit

/// AES-GCM 加密的本地存储。
///
/// 目录布局（目录 0700）：
///   key.bin      — 32 字节随机密钥，0600。
///   history.enc  — 条目元数据 JSON（文本内容内联，图片只有缩略图），整体加密。
///   blobs/<id>   — 图片完整数据，逐文件加密。
///
/// 说明：密钥与数据同机保存，防的是「备份/同步/换机残留/他人翻文件」这类泄露，
/// 不防已拿到本用户权限的攻击者。不用 Keychain 是因为 ad-hoc 签名每次重装都会
/// 触发钥匙串授权弹窗（违背「不要弹窗」的目标）。更高要求可切换「仅内存」模式。
public final class EncryptedDiskStore {
    public let directory: URL
    private let key: SymmetricKey

    private var keyURL: URL { directory.appendingPathComponent("key.bin") }
    private var metaURL: URL { directory.appendingPathComponent("history.enc") }
    private var blobsDir: URL { directory.appendingPathComponent("blobs", isDirectory: true) }

    public enum StoreError: Error {
        case keyCorrupted
    }

    public init(directory: URL) throws {
        self.directory = directory
        let keyPath = directory.appendingPathComponent("key.bin")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        if fm.fileExists(atPath: keyPath.path) {
            let data = try Data(contentsOf: keyPath)
            guard data.count == 32 else { throw StoreError.keyCorrupted }
            key = SymmetricKey(data: data)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let data = newKey.withUnsafeBytes { Data($0) }
            fm.createFile(atPath: keyPath.path, contents: data,
                          attributes: [.posixPermissions: 0o600])
            key = newKey
        }
        try fm.createDirectory(at: directory.appendingPathComponent("blobs", isDirectory: true),
                               withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
    }

    // MARK: - 元数据

    public func loadItems() -> [ClipItem] {
        guard let sealed = try? Data(contentsOf: metaURL),
              let plain = open(sealed) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ClipItem].self, from: plain)) ?? []
    }

    /// 覆盖写入全部元数据，并清理不再被引用的 blob。
    public func saveItems(_ items: [ClipItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let plain = try? encoder.encode(items),
              let sealed = try? seal(plain) else {
            NSLog("ClipVault: 保存历史失败（编码/加密）")
            return
        }
        do {
            try sealed.write(to: metaURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metaURL.path)
        } catch {
            NSLog("ClipVault: 保存历史失败: \(error.localizedDescription)")
        }
        pruneOrphanBlobs(validIDs: Set(items.map(\.id)))
    }

    // MARK: - 图片 blob

    public func writeBlob(id: UUID, data: Data) throws {
        let sealed = try seal(data)
        try sealed.write(to: blobsDir.appendingPathComponent(id.uuidString), options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: blobsDir.appendingPathComponent(id.uuidString).path)
    }

    public func readBlob(id: UUID) -> Data? {
        guard let sealed = try? Data(contentsOf: blobsDir.appendingPathComponent(id.uuidString)) else {
            return nil
        }
        return open(sealed)
    }

    public func deleteBlob(id: UUID) {
        try? FileManager.default.removeItem(at: blobsDir.appendingPathComponent(id.uuidString))
    }

    private func pruneOrphanBlobs(validIDs: Set<UUID>) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: blobsDir.path) else { return }
        for name in names {
            if let id = UUID(uuidString: name), validIDs.contains(id) { continue }
            try? fm.removeItem(at: blobsDir.appendingPathComponent(name))
        }
    }

    /// 删除全部历史数据。密钥文件保留（本实例仍持有该密钥，删掉会导致后续写入无法解密）。
    public func wipeAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: metaURL)
        try? fm.removeItem(at: blobsDir)
        try? fm.createDirectory(at: blobsDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    }

    // MARK: - 加密

    private func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return combined
    }

    private func open(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}
