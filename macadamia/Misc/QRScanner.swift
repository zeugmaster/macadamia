import SwiftUI
import PrettySwiftQR

struct QRScanner: View {
    enum ResultValidation { case valid, retryAfter(Double) }

    @State private var scanner: PrettySwiftQR.QRScanner
    @State private var estimatedPercentComplete = 0.0

    var onResult: ((String) -> ResultValidation)

    init(scanner: PrettySwiftQR.QRScanner = PrettySwiftQR.QRScanner(),
         onResult: @escaping (String) -> ResultValidation) {
        _scanner = State(initialValue: scanner)
        self.onResult = onResult
    }

    // TODO: add haptic feedback to scan success

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            Text("Animated QR code scanner is unavailable when running on macOS.")
                .font(.headline)
        } else {
            QRScannerView(scanner: scanner) { _ in
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        CircularProgressView(progress: $estimatedPercentComplete) {
                            restart()
                        }
                        .padding()
                        .opacity(estimatedPercentComplete > 0 ? 1 : 0)
                    }
            }
            .onChange(of: scanner.progress) { _, progress in
                estimatedPercentComplete = progress?.fraction ?? 0
            }
            .task(id: scanner.state) {
                switch scanner.state {
                case .completed(let result):
                    await handleScanResult(result)
                case .failed:
                    restart()
                default:
                    break
                }
            }
        }
    }

    private func handleScanResult(_ result: ScanResult) async {
        guard let string = result.string else {
            restart()
            return
        }

        switch onResult(string) {
        case .valid:
            estimatedPercentComplete = 1
        case .retryAfter(let delay):
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            restart()
        }
    }

    private func restart() {
        estimatedPercentComplete = 0
        scanner.reset()
    }
}


struct CircularProgressView: View {
    @Binding var progress: Double
    
    var onCancel: (() -> Void)

    @ScaledMetric(relativeTo: .body) private var dimension: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 3
    @ScaledMetric(relativeTo: .body) private var checkSize: CGFloat = 12

    var body: some View {
        Button {
            if progress > 0 && progress < 1 {
                onCancel()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(lineWidth: lineWidth)
                    .foregroundColor(.secondary.opacity(0.5))
                    .shadow(color: .secondary.opacity(0.6), radius: lineWidth * 1.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundColor(.primary)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
                Image(systemName: "checkmark")
                    .font(.system(size: checkSize, weight: .bold))
                    .foregroundColor(.primary)
                    .opacity(progress >= 1 ? 1 : 0)
                    .animation(.spring(), value: progress)
                Image(systemName: "xmark")
                    .font(.system(size: checkSize, weight: .bold))
                    .foregroundColor(.primary)
                    .opacity(progress > 0 && progress < 1 ? 1 : 0)
                    .animation(.spring(), value: progress)
            }
            .frame(width: dimension, height: dimension)
        }
    }
}

struct CircularProgressPreview: View {
    @State private var progress = 0.0

    var body: some View {
        VStack {
            HStack {
                CircularProgressView(progress: $progress) {
                    print("x mark pressed")
                }
            }
            Stepper("Progress: \(Int(progress * 100))%", value: $progress, in: 0...1, step: 0.1)
                .padding()
        }
        .padding()
    }
}

struct CircularProgressView_Previews: PreviewProvider {
    static var previews: some View {
        CircularProgressPreview()
    }
}
