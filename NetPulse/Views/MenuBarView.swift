import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: NetworkMonitorViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.menuBarIcon)
                .font(.system(size: Constants.UI.menuBarIconSize))
                .foregroundColor(.accentColor)
                .imageScale(.medium)

            if !viewModel.menuBarSpeedText.isEmpty {
                Text(viewModel.menuBarSpeedText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }
}
