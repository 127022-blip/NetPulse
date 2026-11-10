import SwiftUI
import AppKit
import Combine

/// 下拉面板视图（CLT/swiftc 可编译：无 @State）
struct DropdownPanelView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @ObservedObject private var theme: AppearancePreference

    init(viewModel: NetworkMonitorViewModel) {
        self.viewModel = viewModel
        self.theme = AppearancePreference.shared
    }

    private var appIconImage: NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 0 {
            return icon
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    private let iconSide: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().padding(.vertical, 8)

            VStack(spacing: Constants.UI.cardSpacing) {
                networkStatusCard
                systemStatusCard
                speedAndWaveformCard
                trafficCard
            }
            .padding(.horizontal, 16)

            Divider().padding(.vertical, 10).padding(.horizontal, 16)

            footerBar
        }
        .frame(width: Constants.UI.panelWidth)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(theme.preferredScheme)
    }

    // MARK: - 标题栏

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSide, height: iconSide)
                .clipShape(RoundedRectangle(cornerRadius: NetPulseAppIcon.cornerRadius(for: iconSide), style: .continuous))
            Text("NetPulse")
                .font(.system(size: 14, weight: .semibold))
            Text(Constants.App.version)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Menu {
                ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                    Button(action: { theme.setMode(mode) }) {
                        if mode == theme.appearanceMode {
                            Text("\(mode.displayName) ✓")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: theme.themeIconName)
                    Text(theme.themeLabel)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .help("主题：\(theme.themeLabel)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - 网络状态

    private var networkStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "网络状态", icon: "network")

            HStack(spacing: 12) {
                Image(systemName: viewModel.networkStatusIcon)
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.isConnected ? .netPulseGreen : .netPulseRed)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.networkTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isConnected ? Color.netPulseGreen : Color.netPulseRed)
                            .frame(width: 6, height: 6)
                        Text(viewModel.isConnected ? "已连接" : "已断开")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if viewModel.locationPermissionNeeded {
                        Text("要显示网络名称，请允许位置权限")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                networkDetailColumn(title: "IP 地址", value: viewModel.ipAddress, monospaced: true, truncateMiddle: true)
                Divider().frame(height: 30)
                networkDetailColumn(title: "网关", value: viewModel.gatewayAddress, monospaced: true, truncateMiddle: true)
                if viewModel.isWiFiInterface {
                    Divider().frame(height: 30)
                    networkDetailColumn(title: "信号强度", value: viewModel.signalStrength, monospaced: false, truncateMiddle: false)
                } else {
                    Divider().frame(height: 30)
                    networkDetailColumn(title: "信号强度", value: "不适用", monospaced: false, truncateMiddle: false)
                }
            }
        }
        .padding(12)
        .cardStyle()
    }

    private func networkDetailColumn(title: String, value: String, monospaced: Bool, truncateMiddle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .lineLimit(1)
                .truncationMode(truncateMiddle ? .middle : .tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 系统状态

    private var systemStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "系统状态", icon: "cpu")

            systemUsageRow(label: "CPU", text: viewModel.statusBarSnapshot.cpuText, percent: viewModel.statusBarSnapshot.cpuPercent, available: true)
            systemUsageRow(label: "MEM", text: viewModel.statusBarSnapshot.memText, percent: viewModel.statusBarSnapshot.memPercent, available: true)
            systemUsageRow(
                label: "SSD",
                text: viewModel.statusBarSnapshot.diskText,
                percent: viewModel.statusBarSnapshot.diskPercent,
                available: viewModel.statusBarSnapshot.diskAvailable
            )
            systemUsageRow(
                label: "TEMP",
                text: viewModel.statusBarSnapshot.cpuTemperatureText,
                percent: temperatureBarPercent(viewModel.statusBarSnapshot.cpuTemperatureCelsius),
                available: viewModel.statusBarSnapshot.cpuTemperatureCelsius != nil,
                emptyBarWhenUnavailable: true
            )
        }
        .padding(12)
        .cardStyle()
    }

    /// 将摄氏度映射为占用条比例：上限 100°C，公式 min(max(celsius, 0) / 100, 1) * 100；读不到返回 0（由 available=false 画空条，不显示 0°）
    private func temperatureBarPercent(_ celsius: Double?) -> Double {
        guard let celsius else { return 0 }
        return min(max(celsius, 0) / 100.0, 1.0) * 100.0
    }

    private func systemUsageRow(label: String, text: String, percent: Double, available: Bool, emptyBarWhenUnavailable: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 36, alignment: .leading)
            if !available && !emptyBarWhenUnavailable {
                Text("磁盘：--")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        if available {
                            Capsule()
                                .fill(Color.usageColor(for: percent))
                                .frame(width: max(2, geo.size.width * CGFloat(min(max(percent, 0), 100) / 100.0)))
                        }
                    }
                }
                .frame(height: 6)
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(available ? Color.usageColor(for: percent) : Color.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .frame(height: 18)
    }

    // MARK: - 实时速度 + 波形

    private var speedAndWaveformCard: some View {
        VStack(spacing: 12) {
            HStack {
                sectionHeader(title: "实时速度", icon: "speedometer")
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Circle().fill(Color.netPulseDownload).frame(width: 6, height: 6)
                    Text("下载").font(.system(size: 10)).foregroundColor(.secondary)
                    Circle().fill(Color.netPulseUpload).frame(width: 6, height: 6)
                    Text("上传").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.netPulseDownload)
                    Text("下载")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(viewModel.downloadSpeedText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.netPulseDownload)
                }
                .frame(maxWidth: .infinity)
                Spacer()
                Divider().frame(height: 50)
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.netPulseUpload)
                    Text("上传")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(viewModel.uploadSpeedText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.netPulseUpload)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Text("速度波形")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            SpeedWaveformView(
                downloadHistory: viewModel.downloadHistoryKBps,
                uploadHistory: viewModel.uploadHistoryKBps
            )
        }
        .padding(12)
        .cardStyle()
    }

    // MARK: - 流量（今日 + 历史）

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("流量")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(TrafficDateLabel.monthDay())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日下行")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.todayDownload)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.netPulseDownload)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日上行")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.todayUpload)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.netPulseUpload)
                }
                Spacer(minLength: 0)
            }

            if viewModel.recentTrafficRecords.isEmpty {
                Text("开始监控后将在此显示近 5 天")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 5) {
                    ForEach(viewModel.recentTrafficRecords.prefix(5)) { record in
                        HStack(spacing: 8) {
                            Text(TrafficDateLabel.display(from: record.date))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer(minLength: 4)
                            Text(ByteFormatter.formatBytes(record.downloadBytes + record.uploadBytes))
                                .font(.system(size: 11, design: .monospaced))
                            if record.peakDownloadSpeed > 0 {
                                Text(ByteFormatter.formatSpeed(record.peakDownloadSpeed))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .cardStyle()
    }

    // MARK: - 底栏

    private var footerBar: some View {
        HStack(spacing: 6) {
            Button(action: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("设置")
                }
            }
            .buttonStyle(NetPulseCapsuleButtonStyle(kind: .secondary))

            Button(action: {
                NotificationCenter.default.post(name: .openAbout, object: nil)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("关于")
                }
            }
            .buttonStyle(NetPulseCapsuleButtonStyle(kind: .secondary))

            Spacer(minLength: 8)

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1, height: 16)

            Button(action: confirmQuit) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("退出")
                }
            }
            .buttonStyle(NetPulseCapsuleButtonStyle(kind: .destructive))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 共用

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "退出 NetPulse？"
        alert.informativeText = "退出 NetPulse 后将停止菜单栏监控"
        alert.alertStyle = .informational
        let quitButton = alert.addButton(withTitle: "退出")
        let cancelButton = alert.addButton(withTitle: "取消")
        quitButton.hasDestructiveAction = true
        quitButton.keyEquivalent = ""
        cancelButton.keyEquivalent = "\r"
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
