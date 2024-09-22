//
//  QRScanner.swift
//  macadamia
//
//  Created by zm on 21.04.24.
//

import SwiftUI
import URUI
import Combine

struct QRScanner: View {
    @ObservedObject var viewModel: QRScannerViewModel

    var body: some View {
        ZStack(alignment:.bottom) {
            if viewModel.isScanning {
                URVideo(videoSession: viewModel.videoSession)
                    
            }
            VStack {
                Spacer()
                HStack {
                    if viewModel.estimatedPercentComplete > 0 {
                        Text("\(Int(viewModel.estimatedPercentComplete * 100))%")
                            .padding()
                    }
                    Spacer()
                    Button {
                        viewModel.restart()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6.0))
    }
}


@MainActor
class QRScannerViewModel: ObservableObject {
    let codesPublisher = URCodesPublisher()
    @Published var videoSession: URVideoSession
    @Published var scanState: URScanState
    @Published var estimatedPercentComplete = 0.0
    @Published var fragmentStates = [URFragmentBar.FragmentState]()
    @Published var result: URScanResult?
    @Published var isScanning = true
    @Published var hrRes: String?

    var onResult: ((String) -> Void)?

    init() {
        videoSession = URVideoSession(codesPublisher: codesPublisher)
        scanState = URScanState(codesPublisher: codesPublisher)
        subscribeToScanState()
    }

    func subscribeToScanState() {
        scanState.resultPublisher.sink { [weak self] result in
            self?.handleScanResult(result: result)
        }.store(in: &cancellables)
    }

    func handleScanResult(result: URScanResult) {
        // Implement the result handling logic, moving it from the QRScanner view
        
        switch result {
        case .failure(_):
            print("failure")
            self.estimatedPercentComplete = 0
        case .other(let result):
            if let onResult = onResult, result.contains("cashu") {
                onResult(result)
            }
            isScanning = false
            estimatedPercentComplete = 1
        case .progress(let progress):
            print(progress)
            self.estimatedPercentComplete = progress.estimatedPercentComplete
        case .reject: 
            print("rejected")
        case .ur(let ur):
            if case .bytes(let urBytes) = ur.cbor {
                if let string = String(data: urBytes, encoding: .utf8),
                   let onResult = onResult {
                    onResult(string)
                    isScanning = false
                    estimatedPercentComplete = 1
                } else {
                    restart()
                }
            }
        }
    }

    func restart() {
        result = nil
        estimatedPercentComplete = 0
        fragmentStates = [.off]
        isScanning = true
        scanState.restart()
    }

    private var cancellables = Set<AnyCancellable>()
}

