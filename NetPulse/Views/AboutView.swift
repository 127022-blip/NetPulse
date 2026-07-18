import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // 应用图标
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            // 应用名称
            Text("NetPulse")
                .font(.system(size: 24, weight: .bold))

            // 版本号
            Text("版本 1.4.6")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            // 版权信息
            Text("Copyright © 2026 GengLei")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(width: 300, height: 200)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
