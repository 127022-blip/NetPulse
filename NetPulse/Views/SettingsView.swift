import SwiftUI

/// 设置视图 - 应用设置页面
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showResetAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()
            }
            .padding()

            Divider()

            // 设置内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 启动设置
                    settingsSection(title: "启动设置", icon: "power") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("启动时自动运行", isOn: $viewModel.launchAtLogin)
                                .font(.system(size: 13))

                            Toggle("后台持续运行", isOn: $viewModel.runInBackground)
                                .font(.system(size: 13))
                        }
                    }

                    // 数据管理
                    settingsSection(title: "数据管理", icon: "chart.bar.doc.horizontal") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: {
                                showResetAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("重置今日流量")
                                }
                                .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)

                            Text("重置后今日流量统计将从零开始")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 350)
        .alert("确认重置", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                viewModel.resetTodayTraffic()
            }
        } message: {
            Text("确定要重置今日流量统计吗？此操作不可撤销。")
        }
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
