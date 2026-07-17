# NetPulse

macOS 菜单栏网速监控工具

## 功能特点

- 📊 **实时网速监控** - 显示上传和下载速度
- 📶 **Wi-Fi 状态显示** - 显示当前连接的无线网络名称
- 🌐 **网络详情** - IP 地址、网关、信号强度
- 📈 **速度波型图** - 可视化网速历史
- 📅 **流量统计** - 今日流量和历史记录
- 🌓 **深色/浅色模式** - 支持手动切换
- 🚀 **轻量高效** - 专为 macOS 菜单栏设计

## 截图

> 截图待添加

## 系统要求

- macOS 12.0 或更高版本

## 安装

### 方法一：下载预编译版本

1. 从 [Releases](https://github.com/127022-blip/NetPulse/releases) 下载最新版本
2. 解压并拖动到应用程序文件夹

### 方法二：从源码编译

```bash
# 克隆项目
git clone https://github.com/127022-blip/NetPulse.git
cd NetPulse

# 安装 XcodeGen（如果未安装）
brew install xcodegen

# 生成项目
xcodegen generate

# 编译
xcodebuild -scheme NetPulse -configuration Release build
```

## 使用

1. 运行 NetPulse.app
2. 网速会显示在菜单栏上
3. 点击菜单栏图标打开详情面板
4. 右键点击菜单栏图标查看选项

## 项目结构

```
NetPulse/
├── App/
│   ├── AppDelegate.swift      # 应用代理
│   └── main.swift             # 入口文件
├── Models/
│   └── NetworkStats.swift     # 数据模型
├── Services/
│   └── NetworkMonitorService.swift  # 网络监控服务
├── ViewModels/
│   └── NetworkMonitorViewModel.swift  # 视图模型
├── Views/
│   ├── DropdownPanelView.swift   # 下拉面板
│   ├── SpeedWaveformView.swift   # 速度波型图
│   └── AboutView.swift           # 关于窗口
├── Utilities/
│   └── ByteFormatter.swift       # 格式化工具
└── Resources/
    └── Info.plist
```

## 技术栈

- Swift 5.9
- SwiftUI + AppKit
- MVVM 架构
- XcodeGen 项目管理

## 开源协议

本项目基于 MIT 协议开源。

## 作者

GengLei

## 贡献

欢迎提交 Issue 和 Pull Request！
