import Foundation

/// 录音相关的全部错误。message 必须是中文，且同时说明发生了什么与下一步做什么。
public enum RecordingEngineError: Error, Equatable, LocalizedError {
    case noInputDevice(String)
    case engineStartFailed(String)
    case formatUnsupported(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noInputDevice(let m), .engineStartFailed(let m),
             .formatUnsupported(let m), .writeFailed(let m):
            return m
        }
    }
}
