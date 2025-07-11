import Combine
import SwiftUI
import URUI

struct QRScanner: View {
    enum ResultValidation { case valid, retryAfter(Double) }
    
    private let codesPublisher: URCodesPublisher

    @State private var videoSession: URVideoSession
    @StateObject private var scanState: URScanState

    @State private var estimatedPercentComplete = 0.0
    @State private var fragmentStates = [URFragmentBar.FragmentState]()
    @State private var result: URScanResult?
    @State private var hrRes: String?
    
    var onResult: ((String) -> ResultValidation)

    init(onResult: @escaping ((String) -> ResultValidation)) {
        self.onResult = onResult
        let codesPublisher = URCodesPublisher()
        self.codesPublisher = codesPublisher
        let videoSession: URVideoSession = .init(codesPublisher: codesPublisher)
        _videoSession = State(wrappedValue: videoSession)
        _scanState = StateObject(wrappedValue: URScanState(codesPublisher: codesPublisher))
    }
    
    // TODO: add haptic feedback to scan success
    
    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            Text("Animated QR code scanner is unavailable when running on macOS.")
                .font(.headline)
        } else {
            URVideo(videoSession: videoSession)
                .overlay(alignment: .bottomLeading, content: {
                    CircularProgressView(progress: $estimatedPercentComplete) {
                        restart()
                    }
                    .padding()
                    .opacity(estimatedPercentComplete > 0 ? 1 : 0)
                })
            .onReceive(scanState.resultPublisher, perform: handleScanResult)
        }
    }

    private func handleScanResult(result: URScanResult) {
        switch result {
        case .failure, .reject:
            estimatedPercentComplete = 0
        case let .other(resultString):
            scanCompleted(string: resultString)
        case let .progress(progress):
            print(progress.estimatedPercentComplete)
            estimatedPercentComplete = progress.estimatedPercentComplete
        case let .ur(ur):
            if case let .bytes(urBytes) = ur.cbor,
               let resultString = String(data: urBytes, encoding: .utf8) {
                scanCompleted(string: resultString)
            } else {
                restart()
            }
        }
    }
    
    private func scanCompleted(string: String) {
        switch onResult(string) {
        case .valid:
            estimatedPercentComplete = 1
        case .retryAfter(let delay):
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: restart)
        }
    }

    private func restart() {
        result = nil
        estimatedPercentComplete = 0
        fragmentStates = [.off]
        scanState.restart()
        videoSession.resetScanningState()
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
