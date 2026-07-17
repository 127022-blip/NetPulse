import SwiftUI

/// 下拉面板视图
struct DropdownPanelView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @State private var isDarkMode: Bool

    init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
        // 初始化深色模式状态
        let appearance = NSApp.effectiveAppearance.name
        _isDarkMode = State(initialValue: appearance == .darkAqua || appearance == .vibrantDark)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("NetPulse")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                // 深色/浅色模式切换按钮
                Button(action: toggleDarkMode) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider().padding(.vertical, 8)

            // 网络状态
            HStack(spacing: 12) {
                Image(systemName: viewModel.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.isConnected ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.wifiName)
                        .font(.system(size: 13, weight: .medium))
                    Text(viewModel.isConnected ? "已连接" : "已断开")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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
                            .foregroundColor(.green)
                        Text("下载")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(viewModel.downloadSpeedText)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                    Divider().frame(height: 50)
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                        Text("上传")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(viewModel.uploadSpeedText)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("下载").font(.system(size: 9)).foregroundColor(.secondary)
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                        Text("上传").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
                
                SpeedWaveformView(
                    downloadHistory: viewModel.speedHistory.map { $0.downloadSpeed / 1024 },
                    uploadHistory: viewModel.speedHistory.map { $0.uploadSpeed / 1024 }
                )
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 今日流量
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("今日流量")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
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
                            .foregroundColor(.blue)
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
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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
                
                ForEach(viewModel.recentTrafficRecords.prefix(5)) { record in
                    HStack {
                        Text(record.date)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down").font(.system(size: 8)).foregroundColor(.green)
                            Text(formatHistoryBytes(record.downloadBytes))
                                .font(.system(size: 10, design: .monospaced))
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up").font(.system(size: 8)).foregroundColor(.blue)
                            Text(formatHistoryBytes(record.uploadBytes))
                                .font(.system(size: 10, design: .monospaced))
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider().padding(.vertical, 12).padding(.horizontal, 16)

            // 底部
            HStack {
                Button(action: {
                    NSApp.orderFrontStandardAboutPanel(nil)
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
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    // MARK: - Helper Methods

    /// 切换深色/浅色模式
    private func toggleDarkMode() {
        isDarkMode.toggle()
    }

    /// 格式化历史流量字节数
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
