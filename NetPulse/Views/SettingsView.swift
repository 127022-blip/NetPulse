import SwiftUI

/// 设置视图 - 应用设置页面
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding()

            Divider()

            // 设置内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 显示设置
                    settingsSection(title: "显示设置", icon: "display") {
                        VStack(alignment: .leading, spacing: 12) {
                            // 菜单栏显示模式
                            HStack {
                                Text("菜单栏显示")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $viewModel.menuBarDisplayMode) {
                                    ForEach(AppSettings.MenuBarDisplayMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                            }

                            // 更新频率
                            HStack {
                                Text("更新频率")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $viewModel.updateInterval) {
                                    Text("0.5秒").tag(0.5)
                                    Text("1秒").tag(1.0)
                                    Text("2秒").tag(2.0)
                                    Text("5秒").tag(5.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                            }
                        }
                    }

                    // 通知设置
                    settingsSection(title: "通知设置", icon: "bell") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("启用通知", isOn: $viewModel.notificationsEnabled)
                                .font(.system(size: 13))

                            if viewModel.notificationsEnabled {
                                Toggle("断网时发送通知", isOn: $viewModel.disconnectNotificationEnabled)
                                    .font(.system(size: 13))
                                    .padding(.leading, 16)

                                Toggle("速度低于阈值时通知", isOn: $viewModel.speedAlertEnabled)
                                    .font(.system(size: 13))
                                    .padding(.leading, 16)

                                if viewModel.speedAlertEnabled {
                                    HStack {
                                        Text("阈值")
                                            .font(.system(size: 13))
                                            .padding(.leading, 32)
                                        Spacer()
                                        TextField("KB/s", value: $viewModel.speedThresholdKB, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                        Text("KB/s")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Toggle("流量超限时通知", isOn: $viewModel.trafficAlertEnabled)
                                    .font(.system(size: 13))
                                    .padding(.leading, 16)

                                if viewModel.trafficAlertEnabled {
                                    HStack {
                                        Text("每日限制")
                                            .font(.system(size: 13))
                                            .padding(.leading, 32)
                                        Spacer()
                                        TextField("GB", value: $viewModel.dailyTrafficLimitGB, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("GB")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            // 授权状态提示
                            if !viewModel.isNotificationAuthorized && viewModel.notificationsEnabled {
                                Button("请求通知权限") {
                                    viewModel.requestNotificationPermission()
                                }
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            }
                        }
                    }

                    // 网络接口设置
                    settingsSection(title: "网络接口", icon: "network") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("选择要监控的网络接口（留空为自动选择）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            ForEach(viewModel.availableInterfaces) { iface in
                                HStack {
                                    Image(systemName: iface.type.systemImage)
                                        .foregroundColor(.accentColor)
                                    Text(iface.displayName)
                                        .font(.system(size: 13))
                                    Spacer()
                                    if viewModel.selectedInterface == iface.name {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedInterface = iface.name
                                }
                            }
                        }
                    }

                    // 启动设置
                    settingsSection(title: "启动设置", icon: "power") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("启动时自动运行", isOn: $viewModel.launchAtLogin)
                                .font(.system(size: 13))

                            Toggle("后台持续运行", isOn: $viewModel.runInBackground)
                                .font(.system(size: 13))
                        }
                    }

                    // 重置设置
                    settingsSection(title: "数据管理", icon: "trash") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("导出流量数据 (CSV)") {
                                viewModel.exportTrafficDataCSV()
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)

                            Button("重置所有设置为默认值") {
                                viewModel.resetToDefaults()
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - 设置区块视图
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
        .cornerRadius(8)
    }
}

// MARK: - 预览
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}
