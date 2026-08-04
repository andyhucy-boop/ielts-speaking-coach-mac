import XCTest
@testable import IELTSCoachCore

final class StateStoreTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    func testLoadCreatesEmptyStateWhenFileMissing() throws {
        let store = StateStore(directory: directory)
        XCTAssertEqual(try store.load().schemaVersion, 3)
    }

    func testMutatePersistsChanges() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.learner.displayName = "Andy" }
        XCTAssertEqual(try StateStore(directory: directory).load().learner.displayName, "Andy")
    }

    func testMutateReturnsBodyResult() throws {
        let store = StateStore(directory: directory)
        let count = try store.mutate { state -> Int in
            state.questions.append(Question(id: "q1", part: 1, topic: "Home", prompt: "Q?"))
            return state.questions.count
        }
        XCTAssertEqual(count, 1)
    }

    func testWriteIsAtomicUnderConcurrentMutation() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.questions = [] }

        // 8 个并发写入，每个追加一题；结束后必须刚好 8 题且文件可解析
        let group = DispatchGroup()
        for index in 0..<8 {
            DispatchQueue.global().async(group: group) {
                try? StateStore(directory: self.directory).mutate {
                    $0.questions.append(Question(id: "q\(index)", part: 1, topic: "T", prompt: "P"))
                }
            }
        }
        group.wait()

        let final = try StateStore(directory: directory).load()
        XCTAssertEqual(final.questions.count, 8)
        XCTAssertEqual(Set(final.questions.map(\.id)).count, 8)
    }

    func testCorruptStateFileProducesChineseError() throws {
        try "这不是 JSON".write(to: directory.stateFile, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try StateStore(directory: directory).load()) { error in
            XCTAssertTrue("\(error)".contains("训练数据文件已损坏"))
        }
    }

    func testDoesNotLeaveTemporaryFilesAfterSuccessfulWrites() throws {
        let store = StateStore(directory: directory)
        for index in 0..<5 {
            try store.mutate { $0.learner.displayName = "写入\(index)" }
        }
        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: directory.root.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "残留了临时文件：\(leftovers)")
    }

    // 上面那条测试测不到 defer 清理是否真的起作用：成功路径下 replaceItemAt 已经把
    // 临时文件移走了，就算把 writeUnlocked 里的 defer { try? FileManager.default
    // .removeItem(at: temporary) } 整段删掉，成功路径下也不会有临时文件残留，断言
    // 恒真。这里构造一个真实会失败的写入：先正常写一次让 state.json 存在，再给它加上
    // NSFileImmutable（chflags uchg 等价物），使后续 replaceItemAt 必然因权限被拒绝
    // 而抛错，逼 defer 真正需要发挥作用把已经写出去的 .tmp 文件清理掉。
    func testDoesNotLeaveTemporaryFilesAfterFailedWrite() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.learner.displayName = "写入前" }

        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: directory.stateFile.path)
        defer {
            // 务必先解除只读，否则 tearDownWithError 里的 removeItem(at: directory.root)
            // 删不掉被锁住的 state.json，临时目录会残留在系统 tmp 里。
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: directory.stateFile.path)
        }

        XCTAssertThrowsError(try store.mutate { $0.learner.displayName = "写入后" },
                             "state.json 被标记为不可变时，写入应当失败")

        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: directory.root.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "写入失败后残留了临时文件：\(leftovers)")
    }
}
