import Foundation
import Testing
@testable import ClipVaultCore

private func textItem(_ s: String, at date: Date = Date(), sensitive: Bool = false,
                      app: String? = nil) -> ClipItem {
    ClipItem(createdAt: date, kind: .text(s), sourceAppBundleID: nil, sourceAppName: app,
             isSensitive: sensitive, contentHash: ContentHasher.hash(text: s))
}

@Suite("HistoryStore")
struct HistoryStoreTests {
    @Test("新条目在最前")
    func newestFirst() {
        let store = HistoryStore()
        store.add(textItem("one"))
        store.add(textItem("two"))
        #expect(store.items.count == 2)
        if case .text(let s) = store.items[0].kind { #expect(s == "two") }
    }

    @Test("重复内容顶到最前并去重")
    func dedupBumpsToTop() {
        let store = HistoryStore()
        store.add(textItem("aaa"))
        store.add(textItem("bbb"))
        let removed = store.add(textItem("aaa"))
        #expect(store.items.count == 2)
        #expect(removed.count == 1)
        if case .text(let s) = store.items[0].kind { #expect(s == "aaa") }
    }

    @Test("按保留时长清理")
    func purgeExpired() {
        var settings = CVSettings.default
        settings.retentionHours = 1
        let store = HistoryStore()
        let now = Date()
        store.add(textItem("old", at: now.addingTimeInterval(-7200)))
        store.add(textItem("fresh", at: now.addingTimeInterval(-60)))
        let removed = store.purge(now: now, settings: settings)
        #expect(removed.count == 1)
        #expect(store.items.count == 1)
        if case .text(let s) = store.items[0].kind { #expect(s == "fresh") }
    }

    @Test("永久保留（retentionHours = 0）不清理")
    func retentionForever() {
        var settings = CVSettings.default
        settings.retentionHours = 0
        let store = HistoryStore()
        store.add(textItem("ancient", at: Date(timeIntervalSince1970: 0)))
        let removed = store.purge(now: Date(), settings: settings)
        #expect(removed.isEmpty)
        #expect(store.items.count == 1)
    }

    @Test("超出最大条数丢弃最旧的")
    func enforcesMaxItems() {
        var settings = CVSettings.default
        settings.maxItems = 3
        settings.retentionHours = 0
        let store = HistoryStore()
        for i in 0..<5 {
            store.add(textItem("item-\(i)"))
        }
        let removed = store.purge(now: Date(), settings: settings)
        #expect(removed.count == 2)
        #expect(store.items.count == 3)
        if case .text(let s) = store.items[0].kind { #expect(s == "item-4") }
        if case .text(let s) = store.items[2].kind { #expect(s == "item-2") }
    }

    @Test("搜索匹配正文与应用名")
    func search() {
        let store = HistoryStore()
        store.add(textItem("deploy billing service", app: "Slack"))
        store.add(textItem("买菜清单", app: "备忘录"))
        #expect(store.search("billing").count == 1)
        #expect(store.search("slack").count == 1)
        #expect(store.search("买菜").count == 1)
        #expect(store.search("不存在的词").isEmpty)
        #expect(store.search("  ").count == 2)
    }

    @Test("敏感条目不参与正文搜索")
    func sensitiveNotSearchableByContent() {
        let store = HistoryStore()
        store.add(textItem("normal-token-text"))
        store.add(textItem("secret-value-abcdef", sensitive: true))
        #expect(store.search("secret-value").isEmpty)
        #expect(store.search("normal-token").count == 1)
    }

    @Test("删除与清空")
    func removeAndClear() {
        let store = HistoryStore()
        let item = textItem("to-remove")
        store.add(item)
        store.add(textItem("stays"))
        #expect(store.remove(id: item.id))
        #expect(store.items.count == 1)
        let ids = store.clear()
        #expect(ids.count == 1)
        #expect(store.items.isEmpty)
    }
}

@Suite("ClipItem")
struct ClipItemTests {
    @Test("敏感条目 preview 遮罩")
    func sensitivePreviewMasked() {
        let item = textItem("super-secret-value-123", sensitive: true)
        #expect(!item.previewText.contains("super"))
        #expect(item.previewText.contains("•"))
    }

    @Test("多行文本折叠为单行 preview")
    func previewCollapsesNewlines() {
        let item = textItem("line1\nline2\tend")
        #expect(!item.previewText.contains("\n"))
        #expect(!item.previewText.contains("\t"))
    }

    @Test("图片 preview 描述")
    func imagePreview() {
        let meta = ImageMeta(byteSize: 2 * 1024 * 1024, pixelWidth: 800, pixelHeight: 600, thumbnailPNG: nil)
        let item = ClipItem(kind: .image(meta), contentHash: "x")
        #expect(item.previewText.contains("800×600"))
        #expect(item.previewText.contains("2.0 MB"))
    }
}
