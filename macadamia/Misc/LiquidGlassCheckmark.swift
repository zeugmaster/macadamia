//
//  LiquidGlassCheckmark.swift
//  macadamia
//

import SwiftUI

/// A large checkmark rendered in Liquid Glass on iOS 26+, falling back to
/// a flat white-with-50%-opacity fill on earlier OS versions.
struct LiquidGlassCheckmark: View {
    var width: CGFloat = 220
    var lineWidth: CGFloat = 28
    var fallbackColor: Color = .white.opacity(0.5)

    private var height: CGFloat { width * 0.75 }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .frame(width: width, height: height)
                    .glassEffect(.clear, in: CheckmarkSolidShape(lineWidth: lineWidth))
            } else {
                CheckmarkSolidShape(lineWidth: lineWidth)
                    .fill(fallbackColor)
                    .frame(width: width, height: height)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }
}

/// A checkmark whose stroke is baked into a closed, fillable path so it can be
/// used directly as a `Shape` for `.glassEffect(in:)` or `.fill(...)`.
struct CheckmarkSolidShape: Shape {
    var lineWidth: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.51))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.10))
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Preview

#Preview("Liquid Glass Checkmark") {
    @Previewable @State var width: Double = 220
    @Previewable @State var lineWidth: Double = 28

    ScrollView {
        LiquidCheckmarkPreviewBackdrop()
    }
    .ignoresSafeArea()
    .overlay {
        LiquidGlassCheckmark(width: width, lineWidth: lineWidth)
    }
    .overlay(alignment: .bottom) {
        VStack(spacing: 10) {
            LiquidCheckmarkTweakRow(label: "Width", value: $width,     range: 80...360, format: "%.0f")
            LiquidCheckmarkTweakRow(label: "Line",  value: $lineWidth, range: 4...60,   format: "%.0f")
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

private struct LiquidCheckmarkTweakRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"

    var body: some View {
        HStack {
            Text(label).frame(width: 56, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption)
    }
}

/// Tall, varied content used as a scrollable backdrop so you can drag textured
/// content under the glass checkmark and see how the material refracts it.
private struct LiquidCheckmarkPreviewBackdrop: View {
    private let sampleParagraph = String(
        repeating: "The quick brown fox jumps over the lazy dog. ",
        count: 24
    )

    var body: some View {
        VStack(spacing: 0) {
            heroBlock
            colorStripes
            textWall(background: .black, foreground: .white, weight: .regular, design: .serif)
            colorGrid
            textWall(background: .indigo, foreground: .white, weight: .heavy, design: .rounded)
            gradientBlock
            textWall(background: Color(white: 0.95), foreground: .black, weight: .regular, design: .monospaced)
            colorStripes
        }
    }

    private var heroBlock: some View {
        ZStack {
            LinearGradient(
                colors: [.pink, .orange, .yellow],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text("Liquid Glass")
                .font(.system(size: 64, weight: .black, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(height: 280)
    }

    private var colorStripes: some View {
        VStack(spacing: 0) {
            ForEach([Color.red, .orange, .yellow, .green, .teal, .blue, .indigo, .purple, .pink], id: \.self) { color in
                Rectangle().fill(color).frame(height: 32)
            }
        }
    }

    private func textWall(
        background: Color,
        foreground: Color,
        weight: Font.Weight,
        design: Font.Design
    ) -> some View {
        Text(sampleParagraph)
            .font(.system(size: 16, weight: weight, design: design))
            .foregroundStyle(foreground)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 0) {
            ForEach(0..<64, id: \.self) { i in
                Rectangle()
                    .fill(Color(hue: Double(i) / 64, saturation: 0.85, brightness: 0.95))
                    .frame(height: 50)
            }
        }
    }

    private var gradientBlock: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 12) {
                Text("Refraction").font(.largeTitle.bold())
                Text("Scroll to drag varied content under the\ncheckmark and watch the material respond.")
                    .font(.title3)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .frame(height: 320)
    }
}
