import SwiftUI

/// 速度波型图视图
struct SpeedWaveformView: View {
    let downloadHistory: [Double]  // KB/s
    let uploadHistory: [Double]    // KB/s
    
    private let maxDisplayCount = 30
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 下载速度波型（绿色）
                WaveformShape(data: downloadHistory, color: .green)
                    .fill(Color.green.opacity(0.6))
                
                // 上传速度波型（蓝色）
                WaveformShape(data: uploadHistory, color: .blue)
                    .fill(Color.blue.opacity(0.4))
                
                // 网格线
                GridLines()
            }
        }
        .frame(height: 60)
    }
}

/// 波型形状
struct WaveformShape: Shape {
    let data: [Double]
    let color: Color
    let maxDisplayCount: Int = 30
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard data.count > 1 else { return path }
        
        let maxValue = data.max() ?? 1
        let normalizedData = data.map { maxValue > 0 ? $0 / maxValue : 0 }
        
        let displayCount = min(maxDisplayCount, 30)
        let stepX = rect.width / CGFloat(displayCount - 1)
        let startX = rect.width - CGFloat(normalizedData.count) * stepX
        
        path.move(to: CGPoint(x: startX, y: rect.maxY))
        
        for (index, value) in normalizedData.enumerated() {
            let x = startX + CGFloat(index) * stepX
            let y = rect.maxY - CGFloat(value) * rect.height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        
        return path
    }
}

/// 网格线
struct GridLines: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // 水平线
                let horizontalLines = 3
                for i in 0...horizontalLines {
                    let y = geometry.size.height * CGFloat(i) / CGFloat(horizontalLines)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                
                // 垂直线
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

/// 波型图预览
struct SpeedWaveformView_Previews: PreviewProvider {
    static var previews: some View {
        SpeedWaveformView(
            downloadHistory: [10, 20, 15, 30, 25, 40, 35, 50, 45, 60, 55, 70, 65, 80, 75, 90, 85, 100, 95, 110],
            uploadHistory: [5, 10, 8, 15, 12, 20, 18, 25, 22, 30, 28, 35, 32, 40, 38, 45, 42, 50, 48, 55]
        )
        .frame(width: 280, height: 60)
        .padding()
    }
}
