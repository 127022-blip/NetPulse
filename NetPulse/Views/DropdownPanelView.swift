import SwiftUI
import AppKit
import Combine

/// 面板主题状态（CLT/swiftc 可编译：无 @State）
private final class PanelThemeState: ObservableObject {
    @Published var appearanceMode: AppSettings.AppearanceMode
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.appearanceMode = AppSettings.load().appearanceMode
        NotificationCenter.default.publisher(for: .settingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appearanceMode = AppSettings.load().appearanceMode
            }
            .store(in: &cancellables)
    }

    var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var themeIconName: String {
        switch appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    func cycleMode() {
        switch appearanceMode {
        case .system: appearanceMode = .light
        case .light: appearanceMode = .dark
        case .dark: appearanceMode = .system
        }
        var s = AppSettings.load()
        s.appearanceMode = appearanceMode
        s.save()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}

/// 下拉面板视图（CLT/swiftc 可编译：无 @State）
struct DropdownPanelView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @ObservedObject private var theme: PanelThemeState

    init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
        self.theme = PanelThemeState()
    }

    private var appIconImage: NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 0 {
            return icon
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 — AppIcon 品牌
            HStack(spacing: 8) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text("NetPulse")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { theme.cycleMode() }) {
                    Image(systemName: theme.themeIconName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("主题：\(theme.appearanceMode.displayName)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider().padding(.vertical, 8)

            // 网络状态
            HStack(spacing: 12) {
                Image(systemName: viewModel.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.isConnected ? .netPulseGreen : .netPulseRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.wifiName)
                        .font(.system(size: 13, weight: .medium))
                    Text(viewModel.isConnected ? "已连接" : "已断开")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(viewModel.isConnected ? Color.netPulseGreen : Color.netPulseRed)
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .cardStyle()
            .padding(.horizontal, 16)

            // 网络详情
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP地址")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.ipAddress)
                        .font(.system(size: 11, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("网关")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.gatewayAddress)
                        .font(.system(size: 11, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("信号强度")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.signalStrength)
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .cardStyle()
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 实时速度
            VStack(spacing: 12) {
                Text("实时速度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.netPulseGreen)
                        Text("下载")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(viewModel.downloadSpeedText)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.netPulseGreen)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                    Divider().frame(height: 50)
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.netPulseBlue)
                        Text("上传")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(viewModel.uploadSpeedText)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.netPulseBlue)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .cardStyle()
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 速度波型图
            VStack(spacing: 4) {
                HStack {
                    Text("速度波型")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Circle().fill(Color.netPulseGreen).frame(width: 6, height: 6)
                        Text("下载").font(.system(size: 9)).foregroundColor(.secondary)
                        Circle().fill(Color.netPulseBlue).frame(width: 6, height: 6)
                        Text("上传").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }

                SpeedWaveformView(
                    downloadHistory: viewModel.speedHistory.map { $0.downloadSpeed / 1024 },
                    uploadHistory: viewModel.speedHistory.map { $0.uploadSpeed / 1024 }
                )
            }
            .padding(12)
            .cardStyle()
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 总使用流量
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("总使用流量")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10))
                            .foregroundColor(.netPulseGreen)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("下载")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(viewModel.todayDownload)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10))
                            .foregroundColor(.netPulseBlue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("上传")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(viewModel.todayUpload)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }
                    Spacer()
                }
            }
            .padding(12)
            .cardStyle()
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 历史流量
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("历史统计")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if viewModel.recentTrafficRecords.isEmpty {
                    Text("暂无历史")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    ForEach(viewModel.recentTrafficRecords.prefix(5)) { record in
                        HStack {
                            Text(record.date)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down").font(.system(size: 8)).foregroundColor(.netPulseGreen)
                                Text(formatHistoryBytes(record.downloadBytes))
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up").font(.system(size: 8)).foregroundColor(.netPulseBlue)
                                Text(formatHistoryBytes(record.uploadBytes))
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .padding(12)
            .cardStyle()
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider().padding(.vertical, 12).padding(.horizontal, 16)

            // 底部
            HStack {
                Button(action: {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gear").font(.system(size: 11))
                        Text("设置").font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 11))
                        Text("关于").font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power").font(.system(size: 11))
                        Text("退出").font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.netPulseRed)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: Constants.UI.panelWidth)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(theme.preferredScheme)
    }

    private func formatHistoryBytes(_ bytes: UInt64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.1fGB", Double(bytes) / (1024 * 1024 * 1024))
        } else if bytes >= 1024 * 1024 {
            return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        } else if bytes >= 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024)
        } else {
            return "\(bytes)B"
        }
    }
}
