import SwiftUI
import AppKit

/// 设置视图（2.0.41 设置窗改版；2.0.42 预览改用 AppIcon）
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var appearance = AppearancePreference.shared
    @FocusState private var speedFieldFocused: Bool
    @FocusState private var trafficFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    menuBarSection
                    appearanceSection
                    refreshSection
                    notificationSection
                    networkInterfaceSection
                    launchSection
                    dataSection
                }
                .padding(16)
            }
        }
        .frame(width: Constants.UI.settingsWindowWidth)
        .frame(
            minHeight: Constants.UI.settingsWindowMinHeight,
            idealHeight: Constants.UI.settingsWindowHeight,
            maxHeight: .infinity
        )
        .preferredColorScheme(appearance.preferredScheme)
        .onAppear { viewModel.refreshNotificationStatus() }
        .onChange(of: speedFieldFocused) { focused in
            if !focused { viewModel.commitSpeedThreshold() }
        }
        .onChange(of: trafficFieldFocused) { focused in
            if !focused { viewModel.commitDailyTrafficLimit() }
        }
    }

    // MARK: - 菜单栏显示

    private var menuBarSection: some View {
        settingsSection(title: "菜单栏显示", icon: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("显示模式")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Picker("", selection: $viewModel.menuBarDisplayMode) {
                    ForEach(AppSettings.MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.isRecommended ? "\(mode.displayName)（推荐）" : mode.displayName)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(viewModel.menuBarDisplayMode.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                menuBarPreview
            }
        }
    }

    /// 假状态栏效果预览（图标与真实菜单栏一致，使用彩色 AppIcon，不用心跳 SF Symbol）
    private var menuBarPreview: some View {
        HStack(spacing: 6) {
            if viewModel.menuBarDisplayMode.showsMenuBarAppIcon {
                previewAppIcon
            }
            previewContent

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(6)
        .accessibilityLabel("菜单栏效果预览")
    }

    private var previewAppIcon: some View {
        Image(nsImage: NetPulseAppIcon.menuBarImage())
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch viewModel.menuBarDisplayMode {
        case .iconOnly:
            // 图标已由 previewAppIcon 展示，此处不再重复文字
            EmptyView()
        case .iconAndSpeed:
            HStack(spacing: 6) {
                Text("↓ 12.3 MB/s")
                    .foregroundColor(Color(hex: "00C7BE"))
                Text("42°")
                    .foregroundColor(Color.temperatureColor(for: 42))
            }
            .font(.system(size: 11, design: .monospaced))
        case .iconAndDualSpeed:
            HStack(spacing: 6) {
                Text("↓ 12.3 MB/s")
                    .foregroundColor(Color(hex: "00C7BE"))
                Text("↑ 1.2 MB/s")
                    .foregroundColor(Color(hex: "007AFF"))
                Text("42°")
                    .foregroundColor(Color.temperatureColor(for: 42))
            }
            .font(.system(size: 11, design: .monospaced))
        case .iconAndSystem:
            // 与真实菜单栏一致：四列同宽（按 TEMP），标签与数值在槽位内水平居中
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text("↑1.2")
                        .foregroundColor(Color(hex: "007AFF"))
                        .frame(width: 40, alignment: .leading)
                    Text("34%")
                        .frame(width: 32, alignment: .center)
                    Text("56%")
                        .frame(width: 32, alignment: .center)
                    Text("62%")
                        .frame(width: 32, alignment: .center)
                    Text("42°")
                        .foregroundColor(Color.temperatureColor(for: 42))
                        .frame(width: 32, alignment: .center)
                }
                HStack(spacing: 0) {
                    Text("↓12.3")
                        .foregroundColor(Color(hex: "00C7BE"))
                        .frame(width: 40, alignment: .leading)
                    Text("CPU")
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .center)
                    Text("MEM")
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .center)
                    Text("SSD")
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .center)
                    Text("TEMP")
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .center)
                }
                .font(.system(size: 9, weight: .regular, design: .monospaced))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.primary)
        case .iconWithCPU:
            HStack(spacing: 0) {
                Text("CPU 34%  ")
                Text("42°")
                    .foregroundColor(Color.temperatureColor(for: 42))
            }
            .font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        settingsSection(title: "外观", icon: "circle.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 12) {
                Text("主题")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { appearance.appearanceMode },
                    set: { appearance.setMode($0) }
                )) {
                    ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - 刷新（独立卡片）

    private var refreshSection: some View {
        settingsSection(title: "刷新", icon: "arrow.clockwise") {
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
            }
        }
    }

    // MARK: - 通知与告警（独立卡片）

    private var notificationSection: some View {
        settingsSection(title: "通知与告警", icon: "bell.badge") {
            VStack(alignment: .leading, spacing: 12) {
                notificationPermissionRow

                Toggle("启用通知", isOn: $viewModel.notificationsEnabled)
                    .font(.system(size: 13))

                if !viewModel.isNotificationAuthorized {
                    Text("系统通知未授权时，子告警不可用。请先授权或前往系统设置开启。")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup(isExpanded: $viewModel.alertsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("告警项目")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        Toggle("网速过慢告警", isOn: $viewModel.speedAlertEnabled)
                            .font(.system(size: 13))
                            .disabled(!viewModel.alertControlsEnabled)

                        if viewModel.speedAlertEnabled {
                            speedThresholdControls
                                .disabled(!viewModel.alertControlsEnabled)
                        }

                        Toggle("断网/恢复通知", isOn: $viewModel.disconnectNotificationEnabled)
                            .font(.system(size: 13))
                            .disabled(!viewModel.alertControlsEnabled)

                        Toggle("每日流量限额提醒", isOn: $viewModel.trafficAlertEnabled)
                            .font(.system(size: 13))
                            .disabled(!viewModel.alertControlsEnabled)

                        if viewModel.trafficAlertEnabled {
                            trafficLimitControls
                                .disabled(!viewModel.alertControlsEnabled)
                        }
                    }
                } label: {
                    Text("告警选项")
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private var notificationPermissionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("通知权限")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.notificationAuthStatusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(viewModel.isNotificationAuthorized ? .netPulseGreen : .orange)
            }

            HStack(spacing: 8) {
                if !viewModel.isNotificationAuthorized {
                    Button("请求授权") {
                        viewModel.requestNotificationPermission()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("打开系统设置") {
                        viewModel.openSystemNotificationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("刷新状态") {
                        viewModel.refreshNotificationStatus()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 主路径：标签 + 当前值 + Slider；精确输入折叠
    private var speedThresholdControls: some View {
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

            DisclosureGroup("精确输入", isExpanded: $viewModel.showSpeedPreciseInput) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("10–1024", text: $viewModel.speedThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 90)
                            .focused($speedFieldFocused)
                            .onSubmit { viewModel.commitSpeedThreshold() }
                        Text("KB/s")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Stepper("", value: $viewModel.speedThresholdKBps, in: 10...1024, step: 10)
                            .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    if !viewModel.speedThresholdError.isEmpty {
                        Text(viewModel.speedThresholdError)
                            .font(.system(size: 11))
                            .foregroundColor(.netPulseRed)
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12))
        }
    }

    private var trafficLimitControls: some View {
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

            DisclosureGroup("精确输入", isExpanded: $viewModel.showTrafficPreciseInput) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("0.5–100", text: $viewModel.dailyTrafficLimitText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 90)
                            .focused($trafficFieldFocused)
                            .onSubmit { viewModel.commitDailyTrafficLimit() }
                        Text("GB")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Stepper("", value: $viewModel.dailyTrafficLimitGB, in: 0.5...100, step: 0.5)
                            .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    if !viewModel.dailyTrafficLimitError.isEmpty {
                        Text(viewModel.dailyTrafficLimitError)
                            .font(.system(size: 11))
                            .foregroundColor(.netPulseRed)
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12))
        }
    }

    // MARK: - 网络接口

    private var networkInterfaceSection: some View {
        settingsSection(title: "网络接口", icon: "network") {
            VStack(alignment: .leading, spacing: 12) {
                Text("统计接口")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if viewModel.availableInterfaces.isEmpty && !viewModel.isRefreshingInterfaces {
                    Text("暂无可用接口，请点击下方刷新")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)
                }

                Picker("", selection: $viewModel.selectedInterface) {
                    Text("自动（单主接口）").tag("")
                    ForEach(viewModel.availableInterfaces) { iface in
                        Text("\(iface.displayName) (\(iface.name))").tag(iface.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(viewModel.isRefreshingInterfaces)

                HStack(spacing: 8) {
                    Button(action: { viewModel.refreshInterfaces() }) {
                        HStack(spacing: 6) {
                            if viewModel.isRefreshingInterfaces {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("刷新接口列表")
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isRefreshingInterfaces)

                    if !viewModel.interfacesRefreshMessage.isEmpty {
                        Text(viewModel.interfacesRefreshMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 启动

    private var launchSection: some View {
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
    }

    // MARK: - 数据管理

    private var dataSection: some View {
        settingsSection(title: "数据管理", icon: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: confirmResetTodayTraffic) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("重置今日流量")
                    }
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.netPulseRed)
                .foregroundColor(.netPulseRed)

                Text("重置后今日流量统计将从零开始")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 2)

                Button(action: confirmResetToDefaults) {
                    HStack {
                        Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                        Text("恢复默认设置")
                    }
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("将刷新间隔、菜单栏模式、告警与主题等恢复为出厂默认")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 确认框

    private func confirmResetTodayTraffic() {
        presentDestructiveSheet(
            title: "重置今日流量？",
            message: "确定要重置今日流量统计吗？此操作不可撤销。",
            destructiveTitle: "重置",
            onConfirm: { viewModel.resetTodayTraffic() }
        )
    }

    private func confirmResetToDefaults() {
        presentDestructiveSheet(
            title: "恢复默认设置？",
            message: "确定将所有设置恢复为默认值吗？今日流量不会被清除。",
            destructiveTitle: "恢复默认",
            onConfirm: { viewModel.resetToDefaults() }
        )
    }

    /// 取消为默认；破坏性按钮在右侧；相对设置窗 beginSheetModal，不用 runModal
    private func presentDestructiveSheet(title: String, message: String, destructiveTitle: String, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        let destructive = alert.addButton(withTitle: destructiveTitle) // 先添加 = 右侧
        let cancel = alert.addButton(withTitle: "取消")
        destructive.hasDestructiveAction = true
        destructive.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        if let window = NSApp.windows.first(where: { $0.title == "设置" && $0.isVisible }) ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    onConfirm()
                }
            }
        }
    }

    // MARK: - 卡片（与主弹窗 cardStyle 一致）

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}
