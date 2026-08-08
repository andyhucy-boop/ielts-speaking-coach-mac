import Foundation
import IELTSCoachCore
import Observation

/// 出错的时候正在干什么。**取值是固定的一组，不是自由文本**——
/// 自由文本迟早会被塞进错误消息。
public enum DiagnosticsStage: String, CaseIterable, Sendable {
    case startingPractice
    case drivingChatGPT
    case fetchingReview
    case parsingReview
    case archivingReview
    case readingState
    case writingState
    case recording
    case importingQuestions
    case buildingPlan

    public var title: String {
        switch self {
        case .startingPractice: return "开始一场练习"
        case .drivingChatGPT: return "操作 ChatGPT"
        case .fetchingReview: return "取回复盘"
        case .parsingReview: return "解析复盘"
        case .archivingReview: return "归档复盘"
        case .readingState: return "读训练数据"
        case .writingState: return "写训练数据"
        case .recording: return "录音"
        case .importingQuestions: return "导入题库"
        case .buildingPlan: return "生成学习计划"
        }
    }
}

/// 一个稳定的错误代号。
///
/// **它替代的是错误原文。** 原文里可能有复盘片段，而复盘片段里全是用户说过的英语；
/// 代号保留了全部排障价值，且不可能包含用户内容。
public enum DiagnosticsCode {
    public static func of(_ error: any Error) -> String {
        if let coach = error as? CoachError {
            // **穷尽的 switch，不写 default。** `CoachError` 将来加一个 case，
            // 这里会当场编译失败；写了 default 的话新错误会安静地并进别人的代号，
            // 而「两个错误共用一个代号」正是 `LastErrorLogTests` 那条测试要拦的事。
            //
            // 计划原文只列了六个 case（`.invalidSessionID` 是计划成文之后才加的），
            // 照抄编不过——这一条与那条测试都补齐到了七个。
            switch coach {
            case .invalidReviewText: return "review-invalid-text"
            case .reviewNotFound: return "review-not-found"
            case .reviewIncomplete: return "review-incomplete"
            case .stateUnreadable: return "state-unreadable"
            case .questionBankInvalid: return "question-bank-invalid"
            case .planImpossible: return "plan-impossible"
            case .invalidSessionID: return "session-id-invalid"
            }
        }
        // 认不出来时用类型与 NSError 的域/码。这两样都不可能带用户内容，
        // 而「未知错误」这种代号等于什么都没记。
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code)"
    }
}

/// 最近一次错误。**只有阶段、代号、时间，没有一个字的错误原文。**
public struct DiagnosticsError: Equatable, Sendable {
    public let occurredAt: String
    public let stage: DiagnosticsStage
    public let code: String

    public init(occurredAt: String, stage: DiagnosticsStage, code: String) {
        self.occurredAt = occurredAt; self.stage = stage; self.code = code
    }

    public var summary: String { "\(occurredAt) · \(stage.title) · \(code)" }
}

/// 进程内的「最近一次错误」。**刻意不落盘**：
/// 它是诊断用的即时信息，不是要跟着数据目录搬到另一台电脑的东西
/// （与「引导看过没有」同一条原则，见 Task 8）。
@MainActor
@Observable
public final class LastErrorLog {
    public static let shared = LastErrorLog()

    public private(set) var last: DiagnosticsError?

    public init() {}

    /// 记一次。**只取阶段与代号**——`error` 的消息一个字都不进来。
    public func record(_ error: any Error, at stage: DiagnosticsStage,
                       now: Date = Date()) {
        last = DiagnosticsError(occurredAt: ISO8601DateFormatter().string(from: now),
                                stage: stage, code: DiagnosticsCode.of(error))
    }

    public func clear() { last = nil }
}

extension PracticeStage {
    /// 这一步失败时，「最近一次错误」里该写「当时在做什么」。
    ///
    /// 穷尽的 `switch`：`PracticeStage` 将来加一步，这里会当场编译失败，
    /// 而不是安静地把它归进一个不相干的阶段。
    var diagnosticsStage: DiagnosticsStage {
        switch self {
        case .idle: return .startingPractice
        case .newChat, .startingVoice, .waitingComposer, .sendingPrompt, .practicing,
             .endingVoice: return .drivingChatGPT
        case .requestingReview, .capturingReview, .needsManualCopy: return .fetchingReview
        // 归档这一步里既写 `pending-reviews/`、又解析复盘、又写 `state.json`，
        // 三样都归「归档复盘」。到底是哪一样由错误代号说清
        // （`review-invalid-text` / `state-unreadable`），不必再切一次阶段。
        case .archiving: return .archivingReview
        // 这两个不是「正在做的事」，是已经有结论的两个终点。`fail` 取的是失败发生前的
        // 那一步，所以正常走不到；真走到了说明是一次失败之后又失败了一次，
        // 而那一定发生在收尾阶段。
        case .done, .failed: return .archivingReview
        // 放弃同样不是「正在做的事」，而且它根本不经过 `fail(_:retry:)`（`cancel()` 直接
        // 把阶段设成 `.abandoned`），所以正常也走不到这里。真走到了，那一定是用户在
        // 本工具正驱动 ChatGPT 的那几步上按了取消——`cancel()` 只有在那时才有意义。
        case .abandoned: return .drivingChatGPT
        }
    }
}
