import Combine
import SwiftUI
import URUI

struct QRScanner: View {
    let codesPublisher: URCodesPublisher

    @StateObject var videoSession: URVideoSession
    @StateObject var scanState: URScanState

    @State private var estimatedPercentComplete = 0.0
    @State private var fragmentStates = [URFragmentBar.FragmentState]()
    @State private var result: URScanResult?
    @State private var isScanning = true
    @State private var hrRes: String?

    var onResult: ((String) -> Void)

    init(onResult: @escaping ((String) -> Void)) {
        self.onResult = onResult
        let codesPublisher = URCodesPublisher()
        self.codesPublisher = codesPublisher
        _videoSession = StateObject(wrappedValue: URVideoSession(codesPublisher: codesPublisher))
        _scanState = StateObject(wrappedValue: URScanState(codesPublisher: codesPublisher))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isScanning {
                URVideo(videoSession: videoSession)
            }
            VStack {
                Spacer()
                HStack {
                    if estimatedPercentComplete > 0 {
                        Text("\(Int(estimatedPercentComplete * 100))%")
                            .padding()
                    }
                    Spacer()
                    Button(action: restart) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6.0))
        .onReceive(scanState.resultPublisher, perform: handleScanResult)
    }

    private func handleScanResult(result: URScanResult) {
        switch result {
        case .failure:
            print("Failure in scanning")
            estimatedPercentComplete = 0
        case let .other(resultString):
            onResult(resultString)
            isScanning = false
            estimatedPercentComplete = 1
        case let .progress(progress):
            print("Scanning progress: \(progress)")
            estimatedPercentComplete = progress.estimatedPercentComplete
        case .reject:
            print("Scan rejected")
        case let .ur(ur):
            if case let .bytes(urBytes) = ur.cbor,
               let resultString = String(data: urBytes, encoding: .utf8) {
                onResult(resultString)
                isScanning = false
                estimatedPercentComplete = 1
            } else {
                restart()
            }
        }
    }

    private func restart() {
        result = nil
        estimatedPercentComplete = 0
        fragmentStates = [.off]
        isScanning = true
        scanState.restart()
    }
}
