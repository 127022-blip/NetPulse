import SwiftUI

/// 速度波形：只画最近 maxDisplayCount 点，上下行共用峰值，先上行后下行
struct SpeedWaveformView: View {
    let downloadHistory: [Double]  // KB/s
    let uploadHistory: [Double]    // KB/s
    var maxDisplayCount: Int = 30

    private var displayDownload: [Double] {
        Array(downloadHistory.suffix(maxDisplayCount))
    }

    private var displayUpload: [Double] {
        Array(uploadHistory.suffix(maxDisplayCount))
    }

    private var sharedPeakKBps: Double {
        max(displayDownload.max() ?? 0, displayUpload.max() ?? 0)
    }

    private var hasData: Bool {
        displayDownload.count > 1 || displayUpload.count > 1
    }

    private var peakLabel: String {
        "峰值 \(ByteFormatter.formatSpeed(sharedPeakKBps * 1024))"
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                GridLines()
                if !hasData {
                    Text("等待速度采样")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    let peak = max(sharedPeakKBps, 1)
                    // 先上行后下行，避免下行完全盖住上行
                    waveformLayer(data: displayUpload, peak: peak, color: .netPulseUpload)
                    waveformLayer(data: displayDownload, peak: peak, color: .netPulseDownload)

                    VStack {
                        HStack {
                            Spacer()
                            Text(peakLabel)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                        Spacer()
                    }
                }
            }
            .frame(height: Constants.UI.waveformHeight)

            HStack {
                Text("–30 秒")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.85))
                Spacer()
                Text("现在")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func waveformLayer(data: [Double], peak: Double, color: Color) -> some View {
        WaveformShape(data: data, sharedPeak: peak, maxDisplayCount: maxDisplayCount, style: .filled)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.20), color.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        WaveformShape(data: data, sharedPeak: peak, maxDisplayCount: maxDisplayCount, style: .line)
            .stroke(color, lineWidth: 1)
    }
}

struct WaveformShape: Shape {
    enum Style {
        case filled
        case line
    }

    let data: [Double]
    let sharedPeak: Double
    var maxDisplayCount: Int = 30
    var style: Style = .filled

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let display = Array(data.suffix(max(maxDisplayCount, 0)))
        guard display.count > 1 else { return path }

        let peak = max(sharedPeak, 1)
        let slots = max(maxDisplayCount, 2)
        let stepX = rect.width / CGFloat(slots - 1)
        // 不足 maxDisplayCount 时靠右对齐，且 startX 不为负
        let startX = max(0, rect.width - CGFloat(display.count - 1) * stepX)

        func point(at index: Int, value: Double) -> CGPoint {
            let x = startX + CGFloat(index) * stepX
            let y = rect.maxY - CGFloat(max(value / peak, 0)) * rect.height
            return CGPoint(x: x, y: y)
        }

        switch style {
        case .line:
            path.move(to: point(at: 0, value: display[0]))
            for (index, value) in display.enumerated().dropFirst() {
                path.addLine(to: point(at: index, value: value))
            }
        case .filled:
            path.move(to: CGPoint(x: startX, y: rect.maxY))
            for (index, value) in display.enumerated() {
                path.addLine(to: point(at: index, value: value))
            }
            let lastX = startX + CGFloat(display.count - 1) * stepX
            path.addLine(to: CGPoint(x: lastX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

struct GridLines: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let horizontalLines = 3
                for i in 0...horizontalLines {
                    let y = geometry.size.height * CGFloat(i) / CGFloat(horizontalLines)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                let verticalLines = 6
                for i in 0...verticalLines {
                    let x = geometry.size.width * CGFloat(i) / CGFloat(verticalLines)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
            }
            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        }
    }
}
