import ImageIO
import XCTest

/// 图标生成流水线的测试。
///
/// 背景：`make-icon.swift` 原来用 `NSImage.lockFocus()` 画位图，在 Retina 屏
/// （backingScaleFactor = 2.0）上产出的像素尺寸是请求尺寸的 2 倍——请求 16×16
/// 拿到 32×32。`iconutil` 遇到尺寸不对的文件会**静默跳过**（退出码仍是 0），
/// 结果 .icns 里只剩 6 种表示，而 `make-icon.sh` 照样打印「✅ 已生成」。
/// 这同时违反「尺寸齐全」和铁律 7「禁止静默失败」。
///
/// 这些测试跑的是真实脚本，不是脚本逻辑的副本——副本不会因为脚本改坏而变红。
final class IconPipelineTests: XCTestCase {

    // MARK: - iconset 的 10 个文件与它们必须具备的像素边长

    /// `iconutil` 认得的固定文件名 → 该文件必须具备的像素边长。
    /// @2x 的文件名里写的是「点」，像素要翻倍——这正是原来搞混的地方。
    private static let expectedPixelSides: [(name: String, side: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
    ]

    // MARK: - 测试：真实脚本产出的 PNG 尺寸

    func testGeneratedPNGsHaveExactlyTheDeclaredPixelSize() throws {
        let run = try IconFixture.correctRun.get()
        XCTAssertEqual(run.status, 0,
                       "make-icon.sh 非零退出。stdout=\(run.stdout) stderr=\(run.stderr)")
        XCTAssertTrue(run.stdout.contains("✅"),
                      "尺寸全部合格时应当打印成功标记。stdout=\(run.stdout)")

        for expected in Self.expectedPixelSides {
            let url = run.iconset.appending(path: expected.name)
            guard let size = Self.pixelSize(of: url) else {
                XCTFail("读不到 \(expected.name) 的像素尺寸（文件可能没生成）")
                continue
            }
            XCTAssertEqual(size.width, expected.side,
                           "\(expected.name) 宽度应为 \(expected.side) 像素，实际 \(size.width)")
            XCTAssertEqual(size.height, expected.side,
                           "\(expected.name) 高度应为 \(expected.side) 像素，实际 \(size.height)")
        }
    }

    // MARK: - 测试：.icns 里表示齐全

    func testGeneratedICNSContainsAllTenRepresentations() throws {
        let run = try IconFixture.correctRun.get()
        let present = try Self.representations(inICNS: run.icns)
        let expected = Set(Self.expectedPixelSides.map(\.name))
        XCTAssertEqual(present, expected,
                       "缺少的表示：\(expected.subtracting(present).sorted())")
    }

    // MARK: - 测试：生成器产出错误尺寸时，make-icon.sh 必须报错退出，不许打印 ✅

    func testMakeIconFailsLoudlyWhenGeneratorProducesWrongSizes() throws {
        // 这个桩生成器复刻了 Retina 上的原始 bug：每个文件都按文件名尺寸的 2 倍写。
        let run = try IconPipeline.run(generatorSource: Self.doubleSizeGeneratorSource)

        XCTAssertNotEqual(run.status, 0,
                          "生成器产出的尺寸全错，make-icon.sh 却成功退出了。stdout=\(run.stdout)")
        XCTAssertFalse(run.stdout.contains("✅"),
                       "尺寸不合格却打印了成功标记，正是铁律 7 禁止的静默失败。stdout=\(run.stdout)")
        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("❌"), "没有给出失败提示。输出=\(message)")
        XCTAssertTrue(message.contains("下一步"),
                      "错误信息没说下一步做什么，不满足中文文案要求。输出=\(message)")
        XCTAssertTrue(message.contains("icon_16x16.png"),
                      "错误信息没指出是哪个文件不合格。输出=\(message)")
    }

    // MARK: - 测试：校验脚本本身抓得住两类问题

    func testVerifyScriptRejectsMissingPNG() throws {
        let good = try IconFixture.correctRun.get()
        let broken = try Self.copyIconset(good.iconset)
        try FileManager.default.removeItem(at: broken.appending(path: "icon_128x128.png"))

        let run = IconPipeline.runVerify(iconset: broken, icns: good.icns,
                                         scriptsRoot: good.scripts)
        XCTAssertNotEqual(run.status, 0, "少了一个 PNG，校验脚本却通过了")
        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("icon_128x128.png"),
                      "错误信息没指出缺的是哪个文件。输出=\(message)")
        XCTAssertTrue(message.contains("下一步"), "错误信息没说下一步做什么。输出=\(message)")
    }

    func testVerifyScriptRejectsICNSMissingRepresentations() throws {
        let good = try IconFixture.correctRun.get()
        // iconset 全对，只把 .icns 换成一个「只打进了 3 种表示」的版本——
        // 这样才能证明校验脚本真的看了 .icns，而不是只看 PNG 尺寸。
        let partialSet = try Self.makeTempDirectory().appending(path: "partial.iconset")
        try FileManager.default.createDirectory(at: partialSet, withIntermediateDirectories: true)
        for name in ["icon_512x512.png", "icon_512x512@2x.png", "icon_256x256.png"] {
            try FileManager.default.copyItem(at: good.iconset.appending(path: name),
                                             to: partialSet.appending(path: name))
        }
        let partialICNS = partialSet.deletingLastPathComponent().appending(path: "partial.icns")
        let convert = IconPipeline.run("/usr/bin/iconutil",
                                       ["-c", "icns", partialSet.path, "-o", partialICNS.path])
        XCTAssertEqual(convert.status, 0, "构造残缺 .icns 失败：\(convert.stderr)")

        let run = IconPipeline.runVerify(iconset: good.iconset, icns: partialICNS,
                                         scriptsRoot: good.scripts)
        XCTAssertNotEqual(run.status, 0, ".icns 只有 3 种表示，校验脚本却通过了")
        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("下一步"), "错误信息没说下一步做什么。输出=\(message)")
    }

    // MARK: - 辅助

    private static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// 把 .icns 反向转回 iconset，得到它实际包含的表示名。
    /// 比自己解析 chunk 更贴近「用户看到的东西」，也不依赖对 chunk 类型码的记忆。
    private static func representations(inICNS icns: URL) throws -> Set<String> {
        let out = try makeTempDirectory().appending(path: "roundtrip.iconset")
        let result = IconPipeline.run("/usr/bin/iconutil",
                                      ["-c", "iconset", icns.path, "-o", out.path])
        guard result.status == 0 else {
            XCTFail("iconutil 反向转换失败：\(result.stderr)")
            return []
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path)
        return Set(names.filter { $0.hasSuffix(".png") })
    }

    private static func copyIconset(_ source: URL) throws -> URL {
        let target = try makeTempDirectory().appending(path: "copy.iconset")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    fileprivate static func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "icon-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 复刻 Retina 上的原始 bug：按文件名尺寸的 2 倍写 PNG。
    private static let doubleSizeGeneratorSource = """
    import AppKit
    let outDir = CommandLine.arguments[1]
    try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for (name, side) in [("icon_\\(base)x\\(base).png", base),
                             ("icon_\\(base)x\\(base)@2x.png", base * 2)] {
            let doubled = side * 2
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: doubled, pixelsHigh: doubled,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = rep.representation(using: .png, properties: [:])!
            try! png.write(to: URL(fileURLWithPath: outDir + "/" + name))
        }
    }
    // 故意不打印任何成功标记：✅ 只能由校验通过后的 make-icon.sh 打印。
    """
}

// MARK: - 跑真实脚本的小工具

enum IconPipeline {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    struct PipelineRun {
        var status: Int32
        var stdout: String
        var stderr: String
        var scripts: URL
        var iconset: URL
        var icns: URL
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
    }

    static func run(_ launchPath: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "启动 \(launchPath) 失败：\(error)")
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }

    /// 把仓库里的 `scripts/` 整个复制到临时目录再跑，产物落在临时目录的 `.build/` 下，
    /// 不碰仓库自己的 `.build`。`generatorSource` 非 nil 时用它替换 `make-icon.swift`，
    /// 以此验证「生成器出问题时打包脚本会不会照样报成功」。
    static func run(generatorSource: String?) throws -> PipelineRun {
        let root = try IconPipelineTests.makeTempDirectory()
        let scripts = root.appending(path: "scripts")
        try FileManager.default.copyItem(at: repositoryRoot.appending(path: "scripts"), to: scripts)
        if let generatorSource {
            try generatorSource.write(to: scripts.appending(path: "make-icon.swift"),
                                      atomically: true, encoding: .utf8)
        }
        let result = run("/bin/bash", [scripts.appending(path: "make-icon.sh").path])
        return PipelineRun(status: result.status, stdout: result.stdout, stderr: result.stderr,
                           scripts: scripts,
                           iconset: root.appending(path: ".build/AppIcon.iconset"),
                           icns: root.appending(path: ".build/AppIcon.icns"))
    }

    static func runVerify(iconset: URL, icns: URL, scriptsRoot: URL) -> Result {
        run("/bin/bash", [scriptsRoot.appending(path: "verify-iconset.sh").path,
                          iconset.path, icns.path])
    }
}

/// 正确产物只生成一次——`swift scripts/make-icon.swift` 每次都要现编译，约 1 秒。
enum IconFixture {
    static let correctRun: Result<IconPipeline.PipelineRun, Error> =
        Result { try IconPipeline.run(generatorSource: nil) }
}
