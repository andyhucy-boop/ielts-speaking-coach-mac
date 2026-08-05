import Foundation

public enum BridgeError: Error, Equatable, LocalizedError {
    case targetNotInstalled(String)
    case accessibilityDenied(String)
    case treeNotAwake(String)
    case elementNotFound(String)
    case stateNotReached(String)
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .targetNotInstalled(let m), .accessibilityDenied(let m), .treeNotAwake(let m),
             .elementNotFound(let m), .stateNotReached(let m), .actionFailed(let m):
            return m
        }
    }
}
