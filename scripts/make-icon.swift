#!/usr/bin/env swift
// 生成 App 图标。零外部依赖，只用系统 AppKit 绘制。
// 用法：swift scripts/make-icon.swift <输出的 .iconset 目录>
//
// 图形：Big Sur 风格圆角方块（品牌紫渐变）+ 白色对话气泡 + 三根声波竖条。
// 不放文字——16pt 下任何文字都会糊成一团。
import AppKit

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "./AppIcon.iconset"

/// 统一的失败出口。绝不静默吞掉错误后继续往下走并打印「✅」——
/// 那会让调用方以为图标生成好了，直到用户在程序坞里看见一张白纸才发现。
func fail(_ what: String, _ nextStep: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(what)\n   下一步：\(nextStep)\n".utf8))
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        atPath: outDir, withIntermediateDirectories: true)
} catch {
    fail("创建输出目录 \(outDir) 失败：\(error.localizedDescription)",
         "确认该路径所在磁盘可写、有剩余空间，然后重跑 ./scripts/make-icon.sh。")
}

let accentTop = NSColor(srgbRed: 0.435, green: 0.396, blue: 0.953, alpha: 1)
let accentBottom = NSColor(srgbRed: 0.278, green: 0.231, blue: 0.788, alpha: 1)

/// 在 1024×1024 画布上绘制，其余尺寸由此缩放而来。
func renderMaster() -> NSImage {
    let side: CGFloat = 1024
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    // Big Sur 图标规范：图形占画布约 80%，四周留白
    let inset = side * 0.10
    let plate = NSRect(x: inset, y: inset,
                       width: side - inset * 2, height: side - inset * 2)
    let squircle = NSBezierPath(roundedRect: plate,
                                xRadius: plate.width * 0.2237,
                                yRadius: plate.width * 0.2237)
    squircle.addClip()
    NSGradient(starting: accentTop, ending: accentBottom)?
        .draw(in: plate, angle: -90)

    // 对话气泡
    let b = NSRect(x: plate.minX + plate.width * 0.20,
                   y: plate.minY + plate.height * 0.28,
                   width: plate.width * 0.60, height: plate.height * 0.44)
    let bubble = NSBezierPath(roundedRect: b,
                              xRadius: b.height * 0.28, yRadius: b.height * 0.28)
    // 气泡尾巴
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: b.minX + b.width * 0.24, y: b.minY + 2))
    tail.line(to: NSPoint(x: b.minX + b.width * 0.20, y: b.minY - b.height * 0.20))
    tail.line(to: NSPoint(x: b.minX + b.width * 0.48, y: b.minY + 2))
    tail.close()
    NSColor.white.setFill()
    bubble.fill()
    tail.fill()

    // 三根声波竖条，高度不等——表示「说话」而不是「静音」
    let ratios: [CGFloat] = [0.40, 0.72, 0.52]
    let barW = b.width * 0.085
    let gap = b.width * 0.115
    let totalW = barW * 3 + gap * 2
    var x = b.midX - totalW / 2
    accentBottom.setFill()
    for r in ratios {
        let h = b.height * r
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: b.midY - h / 2,
                                                   width: barW, height: h),
                               xRadius: barW / 2, yRadius: barW / 2)
        bar.fill()
        x += barW + gap
    }

    image.unlockFocus()
    return image
}

func writePNG(_ source: NSImage, side: Int, to path: String) {
    let target = NSImage(size: NSSize(width: side, height: side))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    target.unlockFocus()

    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fail("生成 \(path) 失败：拿不到图形上下文，画不出位图。",
             "确认运行环境有图形上下文（不能在纯 SSH 会话里跑），在本机图形登录会话里重跑。")
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        fail("写入 \(path) 失败：\(error.localizedDescription)",
             "确认磁盘有剩余空间且该目录可写，然后重跑 ./scripts/make-icon.sh。")
    }
}

let master = renderMaster()
// iconutil 要求的固定文件名，缺一个就打不出 .icns
for base in [16, 32, 128, 256, 512] {
    writePNG(master, side: base, to: "\(outDir)/icon_\(base)x\(base).png")
    writePNG(master, side: base * 2, to: "\(outDir)/icon_\(base)x\(base)@2x.png")
}
print("✅ 图标已生成到 \(outDir)")
