import Foundation
import CryptoKit

/// 图片条目的元数据。完整图片数据不放在这里（走 blob 存储），只保留缩略图用于列表展示。
public struct ImageMeta: Codable, Equatable {
    public let byteSize: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let thumbnailPNG: Data?

    public init(byteSize: Int, pixelWidth: Int, pixelHeight: Int, thumbnailPNG: Data?) {
        self.byteSize = byteSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.thumbnailPNG = thumbnailPNG
    }
}

public enum ClipKind: Codable, Equatable {
    case text(String)
    case image(ImageMeta)
}

public struct ClipItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let kind: ClipKind
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    /// 命中密钥检测且策略为「遮罩」时为 true：列表中不显示明文，但仍可复制。
    public let isSensitive: Bool
    public let contentHash: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ClipKind,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        isSensitive: Bool = false,
        contentHash: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.isSensitive = isSensitive
        self.contentHash = contentHash
    }

    public var isImage: Bool {
        if case .image = kind { return true }
        return false
    }

    public var byteSize: Int {
        switch kind {
        case .text(let s): return s.utf8.count
        case .image(let m): return m.byteSize
        }
    }

    /// 列表里展示的单行预览。敏感条目只显示圆点。
    public var previewText: String {
        switch kind {
        case .text(let s):
            if isSensitive {
                return String(repeating: "•", count: min(24, max(8, s.count)))
            }
            let collapsed = s
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
            return String(collapsed.prefix(200))
        case .image(let m):
            return "图片 \(m.pixelWidth)×\(m.pixelHeight)（\(ByteFormat.string(m.byteSize))）"
        }
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int) -> String {
        let kb = 1024.0, mb = kb * 1024
        let b = Double(bytes)
        if b >= mb { return String(format: "%.1f MB", b / mb) }
        if b >= kb { return String(format: "%.0f KB", b / kb) }
        return "\(bytes) B"
    }
}

public enum ContentHasher {
    public static func hash(text: String) -> String {
        hash(data: Data(text.utf8))
    }

    public static func hash(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
