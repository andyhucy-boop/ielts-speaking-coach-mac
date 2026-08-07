import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    coach — 雅思口语练习

    用法：
      coach doctor                  检查环境是否就绪
      coach questions import <文件>  导入题库（CSV 或 JSON）
      coach questions list [part]   列出题库
      coach practice <题目id>        开始一次练习
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
case "reimport":
    exit(ReimportCommand.run())
case "portability":
    exit(PortabilityCommand.run())
default:
    print("未知命令：\(command)。运行 coach 查看用法。")
    exit(2)
}
