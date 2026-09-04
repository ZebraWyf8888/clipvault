// 端到端测试辅助工具：往系统剪贴板写入指定类型的内容。
// 用法:
//   swift set_pasteboard.swift text "some text"
//   swift set_pasteboard.swift concealed "text with concealed mark"
//   swift set_pasteboard.swift image <width> <height>   （随机噪点图，PNG 压不下去，方便测大小限制）
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: set_pasteboard.swift text|concealed|image ...\n".utf8))
    exit(2)
}

let pb = NSPasteboard.general

switch args[1] {
case "text":
    pb.clearContents()
    pb.setString(args[2], forType: .string)

case "concealed":
    pb.clearContents()
    pb.setString(args[2], forType: .string)
    pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

case "image":
    let w = Int(args[2]) ?? 100
    let h = Int(args[3]) ?? 100
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let raw = rep.bitmapData else { exit(1) }
    for i in 0..<(rep.bytesPerRow * h) {
        raw[i] = UInt8.random(in: 0...255)
    }
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    pb.clearContents()
    pb.setData(png, forType: .png)
    print(png.count)

default:
    exit(2)
}
