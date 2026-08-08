import XCTest

/// 守住一类只在**用户的终端**里发作、在开发机上永远测不出来的 bug。
///
/// bash 在 UTF-8 locale 下会把紧跟在 `$VAR` 后面的多字节字符的头一个字节
/// 当成变量名的一部分。于是这一行：
///
///     echo "版本 $APP_VERSION（构建 $BUILD_NUMBER）"
///
/// 在 `LC_ALL=C` 下正常，在 `LC_ALL=en_US.UTF-8` 下报 `APP_VERSION?: unbound variable`
/// 并在 `set -u` 下直接退出。
///
/// 这个坑真的发作过：2026-08-08 用户第一次跑 `build-app.sh`，App 已经打包成功，
/// 却崩在最后一句打印版本号上。开发机的 shell 恰好是 C locale，所以整晚都是绿的。
///
/// 修法是一个花括号：`${APP_VERSION}`。这条测试保证不会再有人写回去。
final class ShellScriptLocaleSafetyTests: XCTestCase {

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("找不到仓库根（没有 Package.swift 的祖先目录）")
    }

    /// `$VAR` 后面紧跟非 ASCII 字符 —— 必须写成 `${VAR}`。
    private func unsafeExpansions(in source: String) -> [(line: Int, text: String)] {
        var found: [(Int, String)] = []
        for (i, line) in source.components(separatedBy: "\n").enumerated() {
            let scalars = Array(line.unicodeScalars)
            var j = 0
            while j < scalars.count {
                guard scalars[j] == "$" else { j += 1; continue }
                var k = j + 1
                // 变量名：字母或下划线开头，后跟字母数字下划线
                guard k < scalars.count,
                      CharacterSet.letters.contains(scalars[k]) || scalars[k] == "_" else {
                    j += 1; continue
                }
                while k < scalars.count,
                      CharacterSet.alphanumerics.contains(scalars[k]) || scalars[k] == "_" {
                    k += 1
                }
                if k < scalars.count, scalars[k].value > 127 {
                    found.append((i + 1, line.trimmingCharacters(in: .whitespaces)))
                }
                j = k
            }
        }
        return found
    }

    func testNoShellScriptExpandsAVariableRightBeforeAMultibyteCharacter() throws {
        let scripts = try repoRoot().appendingPathComponent("scripts")
        let files = try FileManager.default.contentsOfDirectory(at: scripts, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sh" }

        XCTAssertFalse(files.isEmpty, "scripts/ 下一个 .sh 都没扫到——扫描范围可能写错了，这条测试会恒真")

        var problems: [String] = []
        for file in files {
            for hit in unsafeExpansions(in: try String(contentsOf: file, encoding: .utf8)) {
                problems.append("""
                    \(file.lastPathComponent):\(hit.line) —— `$变量` 后面紧跟着中文标点，\
                    在 UTF-8 locale 下 bash 会把标点的头一个字节算进变量名。
                    实际那一行：\(hit.text)
                    下一步：把这个 `$VAR` 改成 `${VAR}`。
                    """)
            }
        }

        XCTAssertTrue(problems.isEmpty, "\n\n" + problems.joined(separator: "\n\n") + "\n")
    }

    /// 守住上面那把尺子本身：喂一段确实有问题的文本，它必须报得出来。
    func testTheScannerActuallyCatchesTheBugItIsMeantToCatch() {
        // 这一行正是 2026-08-08 真的崩掉的那一行，里面有**两处**：
        // `$APP_VERSION（` 与 `$BUILD_NUMBER）`。第一次写这条测试时我断言成 1 处，
        // 扫描器报 2 才发现是断言写错了，不是扫描器多报。
        let bad = #"echo "版本 $APP_VERSION（构建 $BUILD_NUMBER）""#
        XCTAssertEqual(unsafeExpansions(in: bad).count, 2, "扫描器漏掉了教科书式的例子")

        let good = #"echo "版本 ${APP_VERSION}（构建 ${BUILD_NUMBER}）""#
        XCTAssertTrue(unsafeExpansions(in: good).isEmpty, "花括号写法被误报了")

        let asciiOnly = #"echo "version $APP_VERSION (build $BUILD_NUMBER)""#
        XCTAssertTrue(unsafeExpansions(in: asciiOnly).isEmpty, "纯 ASCII 不该被报")
    }
}
