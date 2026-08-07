import SwiftUI
import UniformTypeIdentifiers

/// 导出用的纯文本文档。`.txt` 与 `.json` 共用它，靠 `contentType` 区分。
///
/// 只含 `String` 与 `UTType`，两者都是 Sendable，所以 Swift 6 的严格并发检查
/// 要它 Sendable 时直接加上即可（`.fileExporter` 会把它跨隔离域搬走）。
struct ExportTextDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    static var writableContentTypes: [UTType] { [.plainText, .json] }

    var text: String
    var contentType: UTType

    init(text: String, contentType: UTType) {
        self.text = text
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
