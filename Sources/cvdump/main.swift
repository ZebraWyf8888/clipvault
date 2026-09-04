import Foundation
import ClipVaultCore

// 调试 / 端到端测试工具：解密并打印历史元数据摘要。
// 敏感条目只输出遮罩后的 preview，永不打印明文。
// 用法: cvdump [数据目录]（默认 ~/Library/Application Support/ClipVault）

struct DumpRow: Codable {
    let kind: String
    let preview: String
    let bytes: Int
    let sensitive: Bool
    let app: String?
    let createdAt: String
}

let args = CommandLine.arguments
let dir: URL
if args.count > 1 {
    dir = URL(fileURLWithPath: args[1], isDirectory: true)
} else {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    dir = base.appendingPathComponent("ClipVault", isDirectory: true)
}

do {
    let store = try EncryptedDiskStore(directory: dir)
    let items = store.loadItems()
    let iso = ISO8601DateFormatter()
    let rows = items.map { item in
        DumpRow(
            kind: item.isImage ? "image" : "text",
            preview: item.previewText,
            bytes: item.byteSize,
            sensitive: item.isSensitive,
            app: item.sourceAppName,
            createdAt: iso.string(from: item.createdAt)
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(rows)
    print(String(data: data, encoding: .utf8) ?? "[]")
} catch {
    FileHandle.standardError.write(Data("cvdump: \(error.localizedDescription)\n".utf8))
    exit(1)
}
