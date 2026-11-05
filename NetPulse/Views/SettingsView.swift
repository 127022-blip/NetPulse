import SwiftUI
import AppKit

/// 设置视图
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection(title: "菜单栏显示", icon: "menubar.rectangle") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("显示模式")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Picker("", selection: $viewModel.menuBarDisplayMode) {
                                ForEach(AppSettings.MenuBarDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    settingsSection(title: "外观", icon: "circle.lefthalf.filled") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("主题")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Picker("", selection: $viewModel.appearanceMode) {
                                ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }

                    settingsSection(title: "刷新与告警", icon: "speedometer") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("刷新间隔")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Picker("", selection: $viewModel.updateInterval) {
                                ForEach(viewModel.intervalOptions, id: \.self) { sec in
                                    Text("\(Int(sec)) 秒").tag(sec)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            Toggle("启用通知", isOn: $viewModel.notificationsEnabled)
                                .font(.system(size: 13))

                            Toggle("网速过慢告警", isOn: $viewModel.speedAlertEnabled)
                                .font(.system(size: 13))
                                .disabled(!viewModel.notificationsEnabled)

                            if viewModel.speedAlertEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("告警阈值")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(viewModel.speedThresholdKBps.rounded())) KB/s")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $viewModel.speedThresholdKBps, in: 10...1024, step: 10)
                                    HStack(spacing: 8) {
                                        TextField("10–1024", text: $viewModel.speedThresholdText)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(width: 90)
                                            .onSubmit { viewModel.commitSpeedThreshold() }
                                        Text("KB/s")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Stepper("", value: $viewModel.speedThresholdKBps, in: 10...1024, step: 10)
                                            .labelsHidden()
                                        Spacer(minLength: 0)
                                    }
                                }
                            }

                            Toggle("断网/恢复通知", isOn: $viewModel.disconnectNotificationEnabled)
                                .font(.system(size: 13))
                                .disabled(!viewModel.notificationsEnabled)

                            Toggle("每日流量限额提醒", isOn: $viewModel.trafficAlertEnabled)
                                .font(.system(size: 13))
                                .disabled(!viewModel.notificationsEnabled)

                            if viewModel.trafficAlertEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("日限额")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1f GB", viewModel.dailyTrafficLimitGB))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $viewModel.dailyTrafficLimitGB, in: 0.5...100, step: 0.5)
                                    HStack(spacing: 8) {
                                        TextField("0.5–100", text: $viewModel.dailyTrafficLimitText)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(width: 90)
                                            .onSubmit { viewModel.commitDailyTrafficLimit() }
                                        Text("GB")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Stepper("", value: $viewModel.dailyTrafficLimitGB, in: 0.5...100, step: 0.5)
                                            .labelsHidden()
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }

                    settingsSection(title: "网络接口", icon: "network") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("统计接口")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Picker("", selection: $viewModel.selectedInterface) {
                                Text("自动（单主接口）").tag("")
                                ForEach(viewModel.availableInterfaces) { iface in
                                    Text("\(iface.displayName) (\(iface.name))").tag(iface.name)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)

                            Button(action: { viewModel.refreshInterfaces() }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("刷新接口列表")
                                }
                                .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection(title: "启动设置", icon: "power") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("启动时自动运行", isOn: $viewModel.launchAtLogin)
                                .font(.system(size: 13))
                            if !viewModel.launchAtLoginHint.isEmpty {
                                Text(viewModel.launchAtLoginHint)
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    settingsSection(title: "数据管理", icon: "chart.bar.doc.horizontal") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: confirmResetTodayTraffic) {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("重置今日流量")
                                }
                                .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.netPulseRed)

                            Text("重置后今日流量统计将从零开始")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 620)
    }

    private func confirmResetTodayTraffic() {
        let alert = NSAlert()
        alert.messageText = "确认重置"
        alert.informativeText = "确定要重置今日流量统计吗？此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.resetTodayTraffic()
        }
    }

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(Constants.UI.cardCornerRadius)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}
