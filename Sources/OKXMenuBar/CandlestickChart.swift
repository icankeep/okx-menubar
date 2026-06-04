import SwiftUI

struct CandlestickChart: View {
    let candles: [Candle]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawGrid(in: &context, size: size)
                drawSupportResistance(in: &context, size: size)
                drawCandles(in: &context, size: size)
            }
            .overlay(alignment: .topTrailing) {
                priceLabels
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .frame(height: 220)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var visibleCandles: [Candle] {
        Array(candles.suffix(60))
    }

    private var priceRange: ClosedRange<Double> {
        let lows = visibleCandles.map(\.low)
        let highs = visibleCandles.map(\.high)
        guard let low = lows.min(), let high = highs.max(), high > low else {
            return 0...1
        }
        let padding = (high - low) * 0.08
        return (low - padding)...(high + padding)
    }

    private var priceLabels: some View {
        let range = priceRange
        return VStack(alignment: .trailing, spacing: 4) {
            Text(NumberFormat.price(range.upperBound))
            Spacer()
            Text(NumberFormat.price((range.upperBound + range.lowerBound) / 2))
            Spacer()
            Text(NumberFormat.price(range.lowerBound))
        }
    }

    private var supportResistance: (support: Double, resistance: Double)? {
        let candles = visibleCandles
        guard let support = candles.map(\.low).min(),
              let resistance = candles.map(\.high).max(),
              resistance > support else {
            return nil
        }
        return (support, resistance)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let style = StrokeStyle(lineWidth: 0.5, dash: [4, 5])
        for index in 1...3 {
            var path = Path()
            let y = size.height * CGFloat(index) / 4
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.18)), style: style)
        }
    }

    private func drawSupportResistance(in context: inout GraphicsContext, size: CGSize) {
        guard let levels = supportResistance else { return }

        let range = priceRange
        let denominator = range.upperBound - range.lowerBound
        guard denominator > 0 else { return }

        func yPosition(_ price: Double) -> CGFloat {
            let ratio = (price - range.lowerBound) / denominator
            return size.height - CGFloat(ratio) * size.height
        }

        drawLevel(
            title: "压力 \(NumberFormat.price(levels.resistance))",
            y: yPosition(levels.resistance),
            color: .red,
            alignment: .top,
            in: &context,
            size: size
        )
        drawLevel(
            title: "支撑 \(NumberFormat.price(levels.support))",
            y: yPosition(levels.support),
            color: .green,
            alignment: .bottom,
            in: &context,
            size: size
        )
    }

    private func drawLevel(
        title: String,
        y: CGFloat,
        color: Color,
        alignment: VerticalAlignment,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
            line,
            with: .color(color.opacity(0.65)),
            style: StrokeStyle(lineWidth: 1, dash: [7, 5])
        )

        let text = Text(title)
            .font(.caption2.monospacedDigit().bold())
            .foregroundColor(color)
        let resolved = context.resolve(text)
        let labelSize = resolved.measure(in: CGSize(width: 160, height: 24))
        let labelX = size.width - labelSize.width - 8
        let offset: CGFloat = alignment == .top ? 4 : -labelSize.height - 4
        let labelY = min(max(4, y + offset), size.height - labelSize.height - 4)
        let background = CGRect(
            x: labelX - 4,
            y: labelY - 2,
            width: labelSize.width + 8,
            height: labelSize.height + 4
        )
        context.fill(
            Path(roundedRect: background, cornerRadius: 4),
            with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        context.draw(resolved, at: CGPoint(x: labelX, y: labelY), anchor: .topLeading)
    }

    private func drawCandles(in context: inout GraphicsContext, size: CGSize) {
        let candles = visibleCandles
        guard !candles.isEmpty else { return }

        let range = priceRange
        let count = CGFloat(candles.count)
        let slotWidth = size.width / count
        let bodyWidth = max(3, slotWidth * 0.58)

        func yPosition(_ price: Double) -> CGFloat {
            let ratio = (price - range.lowerBound) / (range.upperBound - range.lowerBound)
            return size.height - CGFloat(ratio) * size.height
        }

        for (index, candle) in candles.enumerated() {
            let centerX = CGFloat(index) * slotWidth + slotWidth / 2
            let highY = yPosition(candle.high)
            let lowY = yPosition(candle.low)
            let openY = yPosition(candle.open)
            let closeY = yPosition(candle.close)
            let color = candle.isUp ? Color.red : Color.green

            var wick = Path()
            wick.move(to: CGPoint(x: centerX, y: highY))
            wick.addLine(to: CGPoint(x: centerX, y: lowY))
            context.stroke(wick, with: .color(color.opacity(0.9)), lineWidth: 1)

            let top = min(openY, closeY)
            let height = max(1.5, abs(closeY - openY))
            let rect = CGRect(x: centerX - bodyWidth / 2, y: top, width: bodyWidth, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color.opacity(0.78)))
        }
    }
}
