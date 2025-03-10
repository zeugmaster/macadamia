import CoreImage.CIFilterBuiltins
import SwiftUI
import URKit
import URUI

/// A manager class for QR code generation that handles errors and performs operations asynchronously
class QRCodeGenerator {
    private let context = CIContext()
    
    /// Generate QR code asynchronously
    /// - Parameter string: The string to encode in the QR code
    /// - Returns: Optional UIImage if generation succeeds
    func generateQRCode(from string: String) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return nil }
            
            let filter = CIFilter.qrCodeGenerator()
            filter.setValue(Data(string.utf8), forKey: "inputMessage")
            
            guard let qrCodeImage = filter.outputImage else { return nil }
            
            let transformedImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            guard let qrCodeCGImage = self.context.createCGImage(transformedImage, from: transformedImage.extent) else {
                return nil
            }
            
            return UIImage(cgImage: qrCodeCGImage, scale: 1, orientation: .up)
        }.value
    }
}

/// A view that displays a static QR code
struct StaticQR: View {
    let qrCode: UIImage?
    let errorHandler: () -> Void
    
    var body: some View {
        if let qrCode = qrCode {
            Image(uiImage: qrCode)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6.0))
                .accessibilityLabel("QR Code")
        } else {
            Text("Failed to generate QR Code")
                .onAppear(perform: errorHandler)
        }
    }
}

/// View that displays either a static or animated QR code
struct QRView: View {
    let string: String
    @State private var qrImage: UIImage?
    @State private var isLoading = true
    @State private var showError = false
    
    // Using StateObject with proper lifecycle management
    @StateObject private var urDisplayState: URDisplayState
    
    // Constants for better maintainability
    private enum Constants {
        static let staticQRMaxLength = 650
        static let maxFragmentLength = 200
        static let animationFramesPerSecond = 8.0
    }
    
    private let qrGenerator = QRCodeGenerator()
    
    init(string: String) {
        self.string = string
        
        // Create URDisplayState with proper error handling
        do {
            guard let strData = string.data(using: .utf8) else {
                _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: UR.dummy,
                                                                           maxFragmentLen: Constants.maxFragmentLength))
                return
            }
            
            let ur = try UR(type: "bytes", cbor: strData.cbor)
            _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur,
                                                                       maxFragmentLen: Constants.maxFragmentLength))
        } catch {
            print("Error creating UR: \(error.localizedDescription)")
            // Create a dummy URDisplayState as a fallback
            _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: UR.dummy,
                                                                       maxFragmentLen: Constants.maxFragmentLength))
        }
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else if showError {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("QR Generation Failed")
                        .padding()
                    Button("Try Again") {
                        isLoading = true
                        showError = false
                        loadQRCode()
                    }
                    .buttonStyle(.bordered)
                }
            } else if string.count < Constants.staticQRMaxLength {
                StaticQR(qrCode: qrImage) {
                    self.showError = true
                }
                .clipShape(RoundedRectangle(cornerRadius: 6.0))
            } else {
                ZStack {
                    Color(.white)
                    URQRCode(data: .constant(urDisplayState.part),
                             foregroundColor: .black,
                             backgroundColor: .white)
                        .onAppear {
                            startAnimatedQR()
                        }
                        .onDisappear {
                            stopAnimatedQR()
                        }
                        .padding(10)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    stopAnimatedQR()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    startAnimatedQR()
                }
            }
        }
        .onAppear {
            loadQRCode()
        }
    }
    
    private func loadQRCode() {
        Task {
            if string.count < Constants.staticQRMaxLength {
                let image = await qrGenerator.generateQRCode(from: string)
                await MainActor.run {
                    self.qrImage = image
                    self.isLoading = false
                    if image == nil {
                        self.showError = true
                    }
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func startAnimatedQR() {
        urDisplayState.framesPerSecond = Constants.animationFramesPerSecond
        urDisplayState.run()
    }
    
    private func stopAnimatedQR() {
        urDisplayState.stop()
    }
}

// Extension to provide a dummy UR for error cases
extension UR {
    static var dummy: UR {
        do {
            return try UR(type: "bytes", cbor: Data([0]).cbor)
        } catch {
            fatalError("Failed to create dummy UR: \(error)")
        }
    }
}

#Preview {
    QRView(string: "https://example.com")
}
