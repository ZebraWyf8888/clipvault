import Foundation
import Testing
@testable import ClipVaultCore

private func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipvault-test-\(UUID().uuidString)", isDirectory: true)
    return url
}

private func textItem(_ s: String) -> ClipItem {
    ClipItem(kind: .text(s), contentHash: ContentHasher.hash(text: s))
}

@Suite("EncryptedDiskStore")
struct EncryptedDiskStoreTests {
    @Test("元数据加密往返")
    func metaRoundTrip() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedDiskStore(directory: dir)
        let items = [textItem("你好 clipboard"), textItem("second item")]
        store.saveItems(items)

        // 用同一目录新开实例（模拟重启），应能读回
        let store2 = try EncryptedDiskStore(directory: dir)
        let loaded = store2.loadItems()
        #expect(loaded.count == 2)
        #expect(loaded[0].contentHash == items[0].contentHash)
        if case .text(let s) = loaded[0].kind { #expect(s == "你好 clipboard") }
    }

    @Test("磁盘文件不含明文")
    func filesAreEncrypted() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedDiskStore(directory: dir)
        let marker = "PLAINTEXT-MARKER-8f3a"
        store.saveItems([textItem(marker)])

        let raw = try Data(contentsOf: dir.appendingPathComponent("history.enc"))
        #expect(!raw.isEmpty)
        let rawString = String(decoding: raw, as: UTF8.self)
        #expect(!rawString.contains(marker))
        #expect(raw.range(of: Data(marker.utf8)) == nil)
    }

    @Test("blob 加密往返与孤儿清理")
    func blobRoundTripAndPrune() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedDiskStore(directory: dir)
        let keep = textItem("keep")
        let orphanID = UUID()

        try store.writeBlob(id: keep.id, data: Data("image-bytes".utf8))
        try store.writeBlob(id: orphanID, data: Data("orphan-bytes".utf8))
        #expect(store.readBlob(id: keep.id) == Data("image-bytes".utf8))

        // saveItems 只引用 keep，orphan 应被清理
        store.saveItems([keep])
        #expect(store.readBlob(id: keep.id) != nil)
        #expect(store.readBlob(id: orphanID) == nil)
    }

    @Test("密钥与目录权限收紧")
    func permissions() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedDiskStore(directory: dir)
        store.saveItems([textItem("x")])

        let fm = FileManager.default
        let dirPerm = try fm.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        let keyPerm = try fm.attributesOfItem(atPath: dir.appendingPathComponent("key.bin").path)[.posixPermissions] as? Int
        let metaPerm = try fm.attributesOfItem(atPath: dir.appendingPathComponent("history.enc").path)[.posixPermissions] as? Int
        #expect(dirPerm == 0o700)
        #expect(keyPerm == 0o600)
        #expect(metaPerm == 0o600)
    }

    @Test("wipeAll 清空数据且之后仍可写入读回")
    func wipeAll() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedDiskStore(directory: dir)
        let item = textItem("wipe-me")
        try store.writeBlob(id: item.id, data: Data("blob".utf8))
        store.saveItems([item])

        store.wipeAll()
        #expect(store.loadItems().isEmpty)
        #expect(store.readBlob(id: item.id) == nil)

        // wipe 之后继续写，重启后要能读回（密钥没有被破坏）
        store.saveItems([textItem("after-wipe")])
        let store2 = try EncryptedDiskStore(directory: dir)
        #expect(store2.loadItems().count == 1)
    }

    @Test("密钥文件损坏时报错而不是静默用坏数据")
    func corruptedKey() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try EncryptedDiskStore(directory: dir)
        try Data("short".utf8).write(to: dir.appendingPathComponent("key.bin"))
        #expect(throws: EncryptedDiskStore.StoreError.self) {
            _ = try EncryptedDiskStore(directory: dir)
        }
    }
}
