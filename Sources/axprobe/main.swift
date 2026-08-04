import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    axprobe — IELTS Speaking Coach 的 ChatGPT 诊断工具

    用法：
      axprobe doctor              检查环境是否就绪
      axprobe deeplink <url>      打开一个 deep link 并读回输入框内容
      axprobe dump [文件路径]      dump ChatGPT Classic 的完整 AX 树
      axprobe watch [秒数]         持续观察 AX 树变化（用于语音状态探测）
    """)
    exit(2)
}

switch command {
case "doctor":
    exit(Doctor.run())
case "deeplink":
    guard args.count >= 2 else {
        print("用法：axprobe deeplink <url>")
        exit(2)
    }
    exit(DeepLinkExperiment.run(rawURL: args[1]))
case "dump":
    exit(DumpCommand.run(outputPath: args.count >= 2 ? args[1] : nil))
default:
    print("未知命令：\(command)。运行 axprobe 查看用法。")
    exit(2)
}
