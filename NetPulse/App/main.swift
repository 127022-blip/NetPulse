import AppKit

/// 应用入口点
/// 注意：macOS 应用不能使用 @main 属性，必须手动启动
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
