import Foundation
import IELTSCoachCore
import Observation

/// 复训只需要练习驱动的四个能力。**刻意做窄**：`PracticeRunner` 里塞着 AX 驱动、
/// 剪贴板与归档，直接依赖它，本文件的测试就没法在不碰真 ChatGPT 的前提下跑（铁律 5）。
///
/// `finishPractice()` 带 `throws`，照抄的是 `PracticeRunner` 的真实签名。
/// **不为了让协议好看一点去改 `PracticeRunner`**：把它的 `finishPractice()` 改名成
/// `finishPracticeThrowing()` 再包一层 `try?`，等于为了本文件动一条已经跑通的主链路，
/// 还顺手把错误吞掉一次。反过来，`throws` 的要求可以被不抛错的实现满足（Swift 的子类型规则），
/// 假驱动想不抛错随时可以不抛。
@MainActor
public protocol PracticeSessionLauncher: AnyObject {
    var stage: PracticeStage { get }
    /// 本次练习归档后写进 `state.sessions` 的那条记录的 id。未完成时为 nil。
    var finishedSessionID: String? { get }
    func start(setup: SessionSetup) async throws
    func finishPractice() async throws
}

// PracticeRunner 已经具备这四个成员，直接声明遵从，它自己一行都不用改。
extension PracticeRunner: PracticeSessionLauncher {}

/// 跑一场复训会话，并把它挂到复训台账上。
///
/// **挂钩失败必须响。** 复训练完了却没挂上台账，用户会看到「已记录」而进度纹丝不动，
/// 且没有任何线索——这是本项目已知最危险的失败形态（`ArchiveOutcome.skipped` 的注释
/// 写的就是这件事）。所以这个类里每一条走不通的路都会往 `failure` 里写一句
/// 「发生了什么 + 下一步做什么」，没有一条是 `try?` 吞掉的（铁律 7）。
@MainActor
@Observable
public final class RetrainingCoordinator {
    /// 出问题时给用户看的中文说明（发生了什么 + 下一步）。没问题时 nil。
    ///
    /// 一次收尾里可能有不止一件事没走通（例如收尾抛错、同时台账也写不进去），
    /// 那时几句话按发生顺序换行拼在一起——只留最后一句会把先发生的那件事盖掉。
    public private(set) var failure: String?
    /// 成功挂上台账的那条训练记录 id。**没真的挂上时必须是 nil**：
    /// 界面拿它当「这一场已经计入复训进度」的凭据。
    public private(set) var linkedSessionID: String?

    private let launcher: any PracticeSessionLauncher
    private let mutate: ((inout CoachState) -> Void) throws -> Void

    /// - Parameter mutate: 执行一次 state 变更。App 里传
    ///   `{ body in try store.mutate { state in body(&state) } }`；测试里传一个内存容器。
    public init(launcher: any PracticeSessionLauncher,
                mutate: @escaping ((inout CoachState) -> Void) throws -> Void) {
        self.launcher = launcher
        self.mutate = mutate
    }

    /// 开一场复训：先把目标标成「正在练」，再启动练习。
    ///
    /// 标记放在启动之前是刻意的：万一中途崩溃，用户下次打开至少能看到自己选过它，
    /// 而不是回到「还没开始」——练了半场的事实不该被抹掉。
    public func start(target: RetrainingTarget, question: Question,
                      originalQuestionID: String) async {
        failure = nil
        linkedSessionID = nil

        do {
            try mutate { _ = RetrainingLedger.setStatus(.selected, of: target.id, in: &$0) }
        } catch {
            // 标记失败不阻断练习——练习本身比台账重要，但必须说出来。
            report("没能把这个目标标记成「正在复训」：\(error.localizedDescription)",
                   fallbackNextStep: "下一步：练习可以照常进行；练完若复训进度没更新，"
                       + "到「训练记录」页确认这一场是否已存档。")
        }

        do {
            try await launcher.start(
                setup: RetrainingSetupBuilder.makeSetup(target: target, question: question))
        } catch {
            report("这场复训没能启动：\(error.localizedDescription)",
                   fallbackNextStep: "下一步：切到 ChatGPT 看一眼窗口是不是停在对话界面、"
                       + "没有弹窗挡住，然后回到这里再点一次「带着这个目标重练」。")
        }
    }

    /// 练完之后收尾：让驱动把复盘取回并归档，然后把这一场挂到台账上。
    ///
    /// - Parameter originalQuestionID: 目标来源那一场练的是哪道题。**由调用方给，不回查**：
    ///   源 session 允许被单条删除，删掉之后就再也查不到了，而「原题重练还是换题验证」
    ///   必须永远能判定。
    public func finish(target: RetrainingTarget, originalQuestionID: String) async {
        // 收尾抛错**不就此返回**：`PracticeRunner` 是先把这一场写进训练记录、
        // 再去取复盘的（`finishedSessionID` 在归档之前就赋了值），所以抛错时那条记录
        // 已经在了，台账照样得挂。就此返回的话，用户练成的这一场永远不计入复训进度，
        // 而他从界面上看不出任何异常。抛出来的详情驱动自己已经放进 stage 了，
        // 这里再记一句是因为复训流程页上未必看得到那块进度。
        do {
            try await launcher.finishPractice()
        } catch {
            report("这场复训的收尾没走完：\(error.localizedDescription)",
                   fallbackNextStep: "下一步：练习窗口上写着断在哪一步，照那里的按钮重试一次；"
                       + "复盘若还在 ChatGPT 窗口里，先自己复制一份留着。")
        }

        guard let sessionID = launcher.finishedSessionID else {
            report("这场复训已经练完，复盘也走的是原来的存档流程，"
                       + "但没能拿到本次练习的记录编号，因此没挂进复训进度。",
                   fallbackNextStep: "下一步：到「训练记录」页确认这一场在不在；"
                       + "在的话复盘没丢，只是这次不计入「换题验证」的次数。")
            return
        }

        let link = RetrainingLink(targetKey: target.targetKey,
                                  sourceSessionId: target.sourceSessionId,
                                  originalQuestionId: originalQuestionID)
        do {
            var attached = false
            try mutate { attached = RetrainingLedger.attach(link, toSessionWithID: sessionID, in: &$0) }
            if attached {
                linkedSessionID = sessionID
            } else {
                report("这场复训已经存档，但没能挂进复训进度："
                           + "训练记录「\(sessionID)」已经属于另一个复训目标，没有覆盖它。",
                       fallbackNextStep: "下一步：到「训练记录」页看看这一场是不是重复归档了；"
                           + "复盘本身没有丢。")
            }
        } catch {
            report("这场复训已经存档，但写复训进度时出错：\(error.localizedDescription)",
                   fallbackNextStep: "下一步：复盘没有丢；重开一次 App 再看复训中心，"
                       + "若进度仍未更新，请把这条信息反馈给开发者。")
        }
    }

    /// 往 `failure` 里记一句「发生了什么 + 下一步做什么」。
    ///
    /// - Parameter fallbackNextStep: `what` 里已经带了「下一步」时**不再追加**——
    ///   `PracticeRunner` 抛出来的错自带一句可执行的下一步（见它的 `describeFailure`），
    ///   再缀一句自己的只会给出两条互相打架的指示。系统 NSError 不带，那时才补上。
    ///
    /// 拼接而不是覆盖：一次收尾里可能有两件事没走通，只留最后一句会把先发生的盖掉。
    private func report(_ what: String, fallbackNextStep: String) {
        let line = what.contains("下一步") ? what : what + fallbackNextStep
        failure = [failure, line].compactMap { $0 }.joined(separator: "\n")
    }
}
