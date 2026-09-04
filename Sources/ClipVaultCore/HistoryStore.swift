import Foundation

/// 内存中的历史记录（最新的在最前）。只在主线程使用。
public final class HistoryStore {
    public private(set) var items: [ClipItem] = []

    public init(items: [ClipItem] = []) {
        self.items = items
    }

    /// 加入新条目。同内容（hash 相同）的旧条目会被移除（相当于「顶到最前」）。
    /// 返回被移除条目的 id，调用方据此清理对应的 blob。
    @discardableResult
    public func add(_ item: ClipItem) -> [UUID] {
        var removed: [UUID] = []
        if let idx = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            removed.append(items[idx].id)
            items.remove(at: idx)
        }
        items.insert(item, at: 0)
        return removed
    }

    /// 按保留时长和最大条数清理，返回被移除条目的 id。
    @discardableResult
    public func purge(now: Date, settings: CVSettings) -> [UUID] {
        var removed: [UUID] = []
        if settings.retentionHours > 0 {
            let cutoff = now.addingTimeInterval(-Double(settings.retentionHours) * 3600)
            let (keep, drop) = items.stablePartition { $0.createdAt >= cutoff }
            items = keep
            removed.append(contentsOf: drop.map(\.id))
        }
        if settings.maxItems > 0 && items.count > settings.maxItems {
            removed.append(contentsOf: items[settings.maxItems...].map(\.id))
            items = Array(items.prefix(settings.maxItems))
        }
        return removed
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: idx)
        return true
    }

    @discardableResult
    public func clear() -> [UUID] {
        let ids = items.map(\.id)
        items = []
        return ids
    }

    /// 大小写不敏感搜索。敏感条目不参与正文匹配（避免通过搜索探测遮罩内容），
    /// 但可以按来源应用名搜到。
    public func search(_ query: String) -> [ClipItem] {
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

extension Array {
    /// 稳定划分：保持相对顺序，返回 (匹配, 不匹配)。
    func stablePartition(_ belongsInFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for e in self {
            if belongsInFirst(e) { first.append(e) } else { second.append(e) }
        }
        return (first, second)
    }
}
