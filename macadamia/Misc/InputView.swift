import SwiftUI
import AVFoundation
import secp256k1
import Flow

struct InputValidator {
    enum ValidationResult {
        case valid(InputView.Result)
        case invalid(String)
    }
    
    static func validate(_ string: String, supportedTypes: [InputView.InputType]) -> ValidationResult {
        var input = string.removePrefixes(["cashu://", "cashu:", "lightning://", "lightning:"]) // make sure to sort equal prefixes by lenght
        input = input.replacingOccurrences(of: "+", with: "")
        input = input.replacingOccurrences(of: " ", with: "")
        let type: InputView.InputType
        switch input {
        case _ where input.lowercased().hasPrefix("cashu"):
            type = .token
        case _ where input.lowercased().hasPrefix("lnbc"),
            _ where input.lowercased().hasPrefix("lntbs"),
            _ where input.lowercased().hasPrefix("lntb"),
            _ where input.lowercased().hasPrefix("lnbcrt"):
            type = .bolt11Invoice
        case _ where input.lowercased().hasPrefix("lno"):
            type = .bolt12Offer
        case _ where input.lowercased().hasPrefix("creq"):
            type = .creq
        default:
            if let pubkeyData = try? input.bytes,
               let _ = try? secp256k1.Signing.PublicKey(dataRepresentation: pubkeyData,
                                                             format: .compressed) {
                type = .publicKey
            } else {
                return .invalid("Unsupported Input")
            }
        }
        guard supportedTypes.contains(type) else {
            return .invalid("Invalid input: \(type)")
        }
        return .valid(InputView.Result(payload: input, type: type))
    }
}

struct InputView: View {
    struct Result {
        let payload: String
        let type: InputType
    }
    
    enum InputType {
        case bolt11Invoice, bolt12Offer, token, creq, publicKey
    }
    
    private let invalidScanRetryDelay = 3.0
    
    let supportedTypes: [InputType]
    let onResult: (Result) -> Void
    
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    
    @State private var errorMessage: String = "Error message"
    @State private var showError: Bool = false
    
    @State private var restartTag: Int = 0
    
    var body: some View {
        Group {
            if cameraPermissionStatus == .authorized {
                QRScanner { string in
                    checkInput(string) // returns TRUE to the scanner if valid
                }
                .frame(minHeight: 300, maxHeight: 400)
                .overlay {
                    VStack(alignment: .center) {
                        Text(errorMessage)
                        SupportedTypeIndicator(supportedTypes: supportedTypes)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                    .opacity(showError ? 1 : 0)
                }
            } else {
                permissionDeniedView
            }
        }
        .onAppear {
            checkCameraPermission()
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                paste()
            } label: {
                Image(systemName: "list.clipboard")
                    .padding()
                    .shadow(color: .primary, radius: 10)
                    .font(.title2)
            }
        }
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8.0))
    }
    
    private func checkInput(_ string: String) -> QRScanner.ResultValidation {
        switch InputValidator.validate(string, supportedTypes: supportedTypes) {
        case .valid(let result):
            onResult(result)
            return .valid
        case .invalid(let message):
            showErrorMessage(message)
            return .retryAfter(invalidScanRetryDelay)
        }
    }
    
    @MainActor
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        withAnimation {
            showError = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + invalidScanRetryDelay) {
            withAnimation {
                showError = false
            }
        }
    }
    
    @MainActor
    private func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        logger.info("user pasted string \(pasteString.prefix(20) + (pasteString.count < 20 ? "" : "..."))")
        checkInput(pasteString)
    }
    
    private func checkCameraPermission() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        if cameraPermissionStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionStatus = granted ? .authorized : .denied
                }
            }
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .padding(.bottom, 10)
            
            Text("Camera Access Required")
                .font(.headline)
            
            if cameraPermissionStatus == .denied {
                Text("Camera access has been denied. Please enable it in the Settings app to scan QR codes.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if cameraPermissionStatus == .restricted {
                Text("Camera access is restricted. This might be due to parental controls or other restrictions.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Checking camera permissions...")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(minHeight: 300, maxHeight: 400)
        .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
    }
}

struct SupportedTypeIndicator: View {
    let allTypes: [InputView.InputType] = [.bolt11Invoice, .bolt12Offer, .creq, .publicKey, .token]
    let supportedTypes: [InputView.InputType]
    
    var prioritized: [InputView.InputType] {
        allTypes.sorted { a, b in
            supportedTypes.contains(a) && !supportedTypes.contains(b)
        }
    }
    
    func labelForType(_ type: InputView.InputType) -> String {
        var label: String
        switch type {
            case .bolt11Invoice: label = "Invoice"
            case .bolt12Offer:   label = "Offer"
            case .creq:          label = "Request"
            case .publicKey:     label = "Public Key"
            case .token:         label = "Token"
        }
        return label
    }
    
    var body: some View {
        HFlow(spacing: 2) {
            ForEach(prioritized, id:\.self) { type in
                TagView(text: self.labelForType(type))
                    .opacity(supportedTypes.contains(type) ? 1 : 0.3)
                    .font(.caption2)
            }
        }
    }
}

extension String {
    /// Converts a hex string to bytes (Data)
    var bytes: Data {
        get throws {
            // Remove any spaces or non-hex characters
            let hex = self.replacingOccurrences(of: " ", with: "")
            
            // Check if it's a valid hex string
            guard hex.count % 2 == 0 else {
                throw NSError(domain: "Invalid hex string", code: 0, userInfo: nil)
            }
            
            var data = Data()
            var index = hex.startIndex
            
            while index < hex.endIndex {
                let nextIndex = hex.index(index, offsetBy: 2)
                let byteString = hex[index..<nextIndex]
                
                guard let byte = UInt8(byteString, radix: 16) else {
                    throw NSError(domain: "Invalid hex string", code: 0, userInfo: nil)
                }
                
                data.append(byte)
                index = nextIndex
            }
            
            return data
        }
    }
}

/// Removes the given prefixes from the string in the order the appear in the list. This is important to consider when one prefix is contained in the other (e.g. `lightning:` and `lightning://` in which case you must provde the longer prefix first for the function to work.
extension String {
    func removePrefixes(_ prefixes: [String]) -> String {
        var result = self
        for prefix in prefixes {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result.removeSubrange(result.startIndex..<result.index(result.startIndex, offsetBy: prefix.count))
                break // Only remove one prefix
            }
        }
        return result
    }
}
