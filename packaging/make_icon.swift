// 生成 1024x1024 应用图标 PNG（蓝色圆角底 + 剪贴板符号 + 锁角标）。
// 用法: swift make_icon.swift <输出.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// 底：macOS 图标网格大致内缩 10%
let inset: CGFloat = 100
let bgRect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.55, alpha: 1),
])?.draw(in: bgPath, angle: -90)

func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let tinted = NSImage(size: sym.size, flipped: false) { rect in
        sym.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    return tinted
}

// 主体：剪贴板
if let clipboard = tintedSymbol("doc.on.clipboard.fill", pointSize: 430, color: .white) {
    let s = clipboard.size
    let scale = min(520 / s.width, 520 / s.height)
    let w = s.width * scale, h = s.height * scale
    clipboard.draw(in: NSRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2 + 20, width: w, height: h))
}

// 角标：锁（白色圆底）
let badgeCenter = NSPoint(x: 700, y: 280)
let badgeR: CGFloat = 120
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR,
                            width: badgeR * 2, height: badgeR * 2)).fill()
if let lock = tintedSymbol("lock.fill", pointSize: 120,
                           color: NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.55, alpha: 1)) {
    let s = lock.size
    let scale = min(130 / s.width, 130 / s.height)
    let w = s.width * scale, h = s.height * scale
    lock.draw(in: NSRect(x: badgeCenter.x - w / 2, y: badgeCenter.y - h / 2, width: w, height: h))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon written to \(outPath)")
