import AppKit
import Combine
import ClipVaultCore

/// 历史记录的调度中心：策略判定、缩略图生成、加密落盘、清理、回写剪贴板。
final class HistoryController: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let store = HistoryStore()
    private var disk: EncryptedDiskStore?
    private let settings: AppSettingsStore
    /// 仅内存模式下的图片数据缓存（落盘模式直接读 blob）
    private var imageCache: [UUID: Data] = [:]

    private let processQueue = DispatchQueue(label: "com.clipvault.process", qos: .userInitiated)
    private var saveWork: DispatchWorkItem?
    private var purgeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastPersistToDisk: Bool

    static var dataDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["CLIPVAULT_DATA_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClipVault", isDirectory: true)
    }

    init(settings: AppSettingsStore) {
        self.settings = settings
        lastPersistToDisk = settings.value.persistToDisk

        if settings.value.persistToDisk {
            setupDisk()
            for item in disk?.loadItems() ?? [] {
                store.add(item)
            }
            store.purge(now: Date(), settings: settings.value)
            items = store.items
        }

        settings.$value
            .removeDuplicates()
            .sink { [weak self] new in self?.handleSettingsChange(new) }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.purgeTick() }
        RunLoop.main.add(t, forMode: .common)
        purgeTimer = t
    }

    private func setupDisk() {
        do {
            disk = try EncryptedDiskStore(directory: Self.dataDirectory)
        } catch {
            NSLog("ClipVault: 初始化加密存储失败，回退为仅内存模式: \(error.localizedDescription)")
            disk = nil
        }
    }

    // MARK: - 捕获

    func handleCandidate(_ candidate: CaptureCandidate) {
        let current = settings.value

        if let raw = candidate.rawImageData {
            let isPNG = candidate.rawImageIsPNG
            processQueue.async { [weak self] in
                guard let self else { return }
                guard let (png, rep) = Self.normalizeToPNG(raw, alreadyPNG: isPNG) else { return }
                let decision = CapturePolicy.evaluate(
                    text: nil, imageByteCount: png.count, flags: candidate.flags,
                    sourceBundleID: candidate.sourceBundleID, settings: current)
                guard case .acceptImage = decision else { return }
                let thumb = Self.makeThumbnailPNG(from: rep, maxDimension: 256)
                let meta = ImageMeta(byteSize: png.count,
                                     pixelWidth: rep.pixelsWide,
                                     pixelHeight: rep.pixelsHigh,
                                     thumbnailPNG: thumb)
                let item = ClipItem(kind: .image(meta),
                                    sourceAppBundleID: candidate.sourceBundleID,
                                    sourceAppName: candidate.sourceAppName,
                                    isSensitive: false,
                                    contentHash: ContentHasher.hash(data: png))
                DispatchQueue.main.async { self.insert(item, imageData: png) }
            }
            return
        }

        guard let text = candidate.text else { return }
        let decision = CapturePolicy.evaluate(
            text: text, imageByteCount: nil, flags: candidate.flags,
            sourceBundleID: candidate.sourceBundleID, settings: current)
        guard case .acceptText(let sensitive) = decision else { return }
        let item = ClipItem(kind: .text(text),
                            sourceAppBundleID: candidate.sourceBundleID,
                            sourceAppName: candidate.sourceAppName,
                            isSensitive: sensitive,
                            contentHash: ContentHasher.hash(text: text))
        insert(item, imageData: nil)
    }

    private func insert(_ item: ClipItem, imageData: Data?) {
        if let imageData {
            if let disk {
                try? disk.writeBlob(id: item.id, data: imageData)
            } else {
                imageCache[item.id] = imageData
            }
        }
        let removed = store.add(item)
        let purged = store.purge(now: Date(), settings: settings.value)
        for id in removed + purged {
            disk?.deleteBlob(id: id)
            imageCache.removeValue(forKey: id)
        }
        items = store.items
        scheduleSave()
    }

    // MARK: - 读取 / 回写

    func imageData(for item: ClipItem) -> Data? {
        if let cached = imageCache[item.id] { return cached }
        return disk?.readBlob(id: item.id)
    }

    /// 把条目写回系统剪贴板。敏感条目会附带 Concealed 标记，
    /// 让其他剪贴板工具（包括再次经过本应用时）不要记录它。
    func copyToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image:
            if let data = imageData(for: item) {
                pb.setData(data, forType: .png)
            }
        }
        if item.isSensitive {
            pb.setData(Data(), forType: PasteboardWatcher.concealedType)
        }
    }

    // MARK: - 删除

    func delete(_ item: ClipItem) {
        guard store.remove(id: item.id) else { return }
        disk?.deleteBlob(id: item.id)
        imageCache.removeValue(forKey: item.id)
        items = store.items
        scheduleSave()
    }

    func clearAll() {
        let ids = store.clear()
        for id in ids {
            imageCache.removeValue(forKey: id)
        }
        disk?.wipeAll()
        items = []
    }

    // MARK: - 落盘

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        disk?.saveItems(store.items)
    }

    private func purgeTick() {
        let removed = store.purge(now: Date(), settings: settings.value)
        guard !removed.isEmpty else { return }
        for id in removed {
            disk?.deleteBlob(id: id)
            imageCache.removeValue(forKey: id)
        }
        items = store.items
        scheduleSave()
    }

    // MARK: - 设置变更

    private func handleSettingsChange(_ new: CVSettings) {
        if new.persistToDisk != lastPersistToDisk {
            lastPersistToDisk = new.persistToDisk
            if new.persistToDisk {
                // 内存 → 落盘：建立存储并把现有内容写进去
                setupDisk()
                if let disk {
                    for (id, data) in imageCache {
                        try? disk.writeBlob(id: id, data: data)
                    }
                    imageCache.removeAll()
                    disk.saveItems(store.items)
                }
            } else {
                // 落盘 → 仅内存：先把图片捞回内存，再擦除磁盘
                if let disk {
                    for item in store.items where item.isImage {
                        if let data = disk.readBlob(id: item.id) {
                            imageCache[item.id] = data
                        }
                    }
                    disk.wipeAll()
                }
                disk = nil
            }
        }
        purgeTick()
    }

    // MARK: - 图片处理

    private static func normalizeToPNG(_ raw: Data, alreadyPNG: Bool) -> (Data, NSBitmapImageRep)? {
        guard let rep = NSBitmapImageRep(data: raw) else { return nil }
        if alreadyPNG {
            return (raw, rep)
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, rep)
    }

    private static func makeThumbnailPNG(from rep: NSBitmapImageRep, maxDimension: Int) -> Data? {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        let scale = min(1.0, Double(maxDimension) / Double(max(w, h)))
        let tw = max(1, Int(Double(w) * scale))
        let th = max(1, Int(Double(h) * scale))
        guard let thumbRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        guard let ctx = NSGraphicsContext(bitmapImageRep: thumbRep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .medium
        rep.draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()
        return thumbRep.representation(using: .png, properties: [:])
    }
}
