import SwiftUI

/// 迷你窗口视图 - 悬浮在屏幕上的小窗口，持续显示网速
struct MiniWindowView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 6) {
            // 下载速度
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.netPulseGreen)

                Text(viewModel.downloadSpeedText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.netPulseGreen)
            }

            // 上传速度
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.netPulseBlue)

                Text(viewModel.uploadSpeedText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.netPulseBlue)
            }

            // 连接状态
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.isConnected ? Color.netPulseGreen : Color.netPulseRed)
                    .frame(width: 6, height: 6)

                Text(viewModel.activeInterfaceName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

/// 迷你窗口容器 - 包含窗口装饰
struct MiniWindowContainer: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
                MiniWindowView(viewModel: viewModel)
            }
            .frame(width: 120)
            .padding(8)
        }
    }
}

// MARK: - 预览
struct MiniWindowView_Previews: PreviewProvider {
    static var previews: some View {
        MiniWindowView(viewModel: NetworkMonitorViewModel(
            networkService: NetworkMonitorService()
        ))
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.gray.opacity(0.3))
    }
}
