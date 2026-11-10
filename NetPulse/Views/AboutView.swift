import SwiftUI
import AppKit

struct AboutView: View {
    var onClose: () -> Void

    @ObservedObject private var appearance = AppearancePreference.shared

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? Constants.App.version
    }

    private var buildText: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build ?? Constants.App.build
    }

    private var copyrightText: String {
        if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String,
           !copyright.isEmpty {
            return copyright
        }
        return "Copyright © 2026 Geng Lei"
    }

    private let iconSide: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            // 固定高度避开交通灯；不用弹性 Spacer，避免剩余高度全堆到图标上方
            Color.clear.frame(height: 22)

            VStack(spacing: 0) {
                // 光晕只绘制、不占布局高度，避免 iconSide×1.55 把图标上方撑空
                ZStack {
                    RadialGradient(
                        colors: [
                            Color.netPulseDownload.opacity(0.09),
                            Color.netPulseDownload.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: iconSide * 0.9
                    )
                    .frame(width: iconSide * 1.55, height: iconSide * 1.55)
                    .allowsHitTesting(false)

                    Image(nsImage: NetPulseAppIcon.sourceImage())
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSide, height: iconSide)
                        // icns 已含圆角 alpha：统一 22% 裁切，但不叠外阴影，避免双裁切发灰
                        .clipShape(RoundedRectangle(cornerRadius: NetPulseAppIcon.cornerRadius(for: iconSide), style: .continuous))
                }
                .frame(width: iconSide, height: iconSide)

                Text("NetPulse")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 6)

                Text("版本 \(versionText)（\(buildText)）")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)

                Text(copyrightText)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .textSelection(.enabled)
                    .padding(.top, 2)

                Button(action: onClose) {
                    Text("完成")
                        .frame(minWidth: 56)
                }
                .buttonStyle(NetPulseAboutDoneButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.horizontal, 24)
        }
        .frame(width: Constants.UI.aboutWindowWidth, height: Constants.UI.aboutWindowHeight)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(appearance.preferredScheme)
        .onExitCommand(perform: onClose)
    }
}

/// 仅用于关于窗口「完成」：接近系统普通按钮的克制样式，不用高饱和宽胶囊。
/// 不影响弹窗等处对 NetPulseCapsuleButtonStyle 的使用。
private struct NetPulseAboutDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlColor))
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
    }
}
