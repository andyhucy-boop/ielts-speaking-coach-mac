import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    coach — 雅思口语练习

    用法：
      coach doctor                  检查环境是否就绪
      coach questions import <文件>  导入题库（.csv / .json / .pdf）
      coach questions list [part]   列出题库
      coach questions remodel       把旧结构题库改成「一个话题一道题」
                                    （默认只预演，加 --apply 才写盘，写盘前自动备份）
      coach practice <题目id>        开始一次练习
      coach prompt [--part 1|2|3|2+3|mock]
                                    打印发给 ChatGPT 的考官提示词全文（不碰 ChatGPT）
                                    可加 --question <题目id> 用自己的题，
                                    以及 --immediate / --self-paced / --goal <文字>
      coach reimport                把已保存但未入库的复盘重新归档
      coach portability             检查数据目录能否原样搬到另一台电脑
    """)
    exit(2)
}

switch command {
case "doctor":
    exit(DoctorCommand.run())
case "questions":
    exit(QuestionsCommand.run(Array(args.dropFirst())))
case "practice":
    exit(PracticeCommand.run(Array(args.dropFirst())))
case "prompt":
    exit(PromptCommand.run(Array(args.dropFirst())))
case "reimport":
    exit(ReimportCommand.run())
case "portability":
    exit(PortabilityCommand.run())
default:
    print("未知命令：\(command)。运行 coach 查看用法。")
    exit(2)
}
