import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    axprobe — IELTS Speaking Coach 的 ChatGPT 诊断工具

    用法：
      axprobe doctor              检查环境是否就绪
      axprobe press <desc>        按下指定 description 的按钮（实测用）
      axprobe dump [文件路径]      dump 目标应用（ChatGPT 新版）的完整 AX 树
    """)
    exit(2)
}

switch command {
case "doctor":
    exit(Doctor.run())
case "dump":
    exit(DumpCommand.run(outputPath: args.count >= 2 ? args[1] : nil))
case "press":
    guard args.count >= 2 else {
        print("用法：axprobe press \"<按钮的 description>\"，例如 axprobe press \"New voice chat\"")
        exit(2)
    }
    exit(PressCommand.run(description: args[1]))
default:
    print("未知命令：\(command)。运行 axprobe 查看用法。")
    exit(2)
}
