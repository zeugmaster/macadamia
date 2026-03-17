import SwiftUI
import AVFoundation
import secp256k1
import Flow
import LNURL_Swift

// MARK: - BIP-321 URI Parser

/// Parses BIP-321 `bitcoin:` URIs and extracts payment instructions.
/// Prioritizes: cashu payment request (creq) > BOLT11 invoice (lightning) > unsupported.
struct BIP321 {
    
    /// Represents the result of parsing a BIP-321 URI.
    struct ParsedURI {
        let address: String?         // on-chain bitcoin address (may be empty)
        let amount: String?          // BTC amount
        let label: String?
        let message: String?
        let lightning: String?       // BOLT11 invoice
        let lno: String?             // BOLT12 offer
        let creq: String?            // cashu payment request
        let otherParams: [String: String]
    }
    
    /// Checks whether a string is a BIP-321 bitcoin: URI.
    static func isBitcoinURI(_ string: String) -> Bool {
        string.lowercased().hasPrefix("bitcoin:")
    }
    
    /// Parses a BIP-321 URI string into its components.
    /// Returns nil if the string is not a valid bitcoin: URI.
    static func parse(_ string: String) -> ParsedURI? {
        let lowered = string.lowercased()
        guard lowered.hasPrefix("bitcoin:") else { return nil }
        
        // Remove scheme prefix (case-insensitive)
        let withoutScheme = String(string.dropFirst("bitcoin:".count))
        
        // Split on '?' to separate address from query params
        let parts = withoutScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let address: String? = parts.first.map { String($0) }.flatMap { $0.isEmpty ? nil : $0 }
        
        var params: [String: String] = [:]
        if parts.count > 1 {
            let queryString = String(parts[1])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                let key = String(kv[0]).lowercased()
                let value = kv.count > 1 ? String(kv[1]).removingPercentEncoding ?? String(kv[1]) : ""
                params[key] = value
            }
        }
        
        return ParsedURI(
            address: address,
            amount: params["amount"],
            label: params["label"],
            message: params["message"],
            lightning: params["lightning"],
            lno: params["lno"],
            creq: params["creq"],
            otherParams: params
        )
    }
    
    /// Resolves a BIP-321 URI to the best supported payment method.
    /// Priority: creq > lightning (BOLT11) > unsupported.
    static func resolve(_ string: String, supportedTypes: [InputView.InputType]) -> InputValidator.ValidationResult {
        guard let parsed = parse(string) else {
            return .invalid(String(localized: "Unsupported Input"))
        }
        
        // Priority 1: cashu payment request
        if let creq = parsed.creq, !creq.isEmpty, supportedTypes.contains(.creq) {
            return .valid(InputView.Result(payload: creq, type: .creq))
        }
        
        // Priority 2: BOLT11 lightning invoice
        if let lightning = parsed.lightning, !lightning.isEmpty, supportedTypes.contains(.bolt11Invoice) {
            return .valid(InputView.Result(payload: lightning, type: .bolt11Invoice))
        }
        
        // BOLT12 offers are not yet supported
        if let lno = parsed.lno, !lno.isEmpty {
            return .invalid(String(localized: "BOLT12 is not yet supported"))
        }
        
        // On-chain bitcoin addresses are not supported in this wallet
        if parsed.address != nil {
            return .invalid(String(localized: "On-chain Bitcoin payments are not supported"))
        }
        
        return .invalid(String(localized: "No supported payment method found in bitcoin URI"))
    }
}

// MARK: - Input Validator

struct InputValidator {
    enum ValidationResult {
        case valid(InputView.Result)
        case invalid(String)
    }
    
    static func validate(_ string: String, supportedTypes: [InputView.InputType]) -> ValidationResult {
        var input = string.removePrefixes(["cashu://", "cashu:", "lightning://", "lightning:"]) // make sure to sort equal prefixes by lenght
        input = input.replacingOccurrences(of: "+", with: "")
        input = input.replacingOccurrences(of: " ", with: "")
        
        // Check for BIP-321 bitcoin: URI before other type detection
        if BIP321.isBitcoinURI(input) {
            return BIP321.resolve(input, supportedTypes: supportedTypes)
        }
        
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
        case _ where input.lowercased().hasPrefix("lnurl"):
            type = .lnurlPay
        case _ where isLightningAddress(input):
            type = .lightningAddress
        case _ where MerchantParser.isMerchantQRCode(input):
            type = .merchantCode
        default:
            if let pubkeyData = try? input.bytes,
               let _ = try? secp256k1.Signing.PublicKey(dataRepresentation: pubkeyData,
                                                             format: .compressed) {
                type = .publicKey
            } else {
                return .invalid(String(localized: "Unsupported Input"))
            }
        }
        guard supportedTypes.contains(type) else {
            return .invalid(String(localized: "Invalid input: \(String(describing: type))"))
        }
        // For merchant codes, convert to lightning address before returning
        if type == .merchantCode {
            guard let lightningAddress = MerchantParser.convertMerchantQRToLightningAddress(qrContent: input, network: .mainnet) else {
                return .invalid(String(localized: "Could not parse merchant code"))
            }
            return .valid(InputView.Result(payload: lightningAddress, type: .merchantCode))
        }
        return .valid(InputView.Result(payload: input, type: type))
    }
    
    private static func isLightningAddress(_ string: String) -> Bool {
        let components = string.split(separator: "@")
        guard components.count == 2 else { return false }
        let username = components[0]
        let domain = components[1]
        guard !username.isEmpty, !domain.isEmpty else { return false }
        return domain.contains(".")
    }
}

struct InputView: View {
    struct Result: Hashable {
        let payload: String
        let type: InputType
    }
    
    enum InputType: Hashable {
        case bolt11Invoice, bolt12Offer, token, creq, publicKey, lnurlPay, lightningAddress, merchantCode
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
    
    @discardableResult
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
    let allTypes: [InputView.InputType] = [.bolt11Invoice, .bolt12Offer, .creq, .publicKey, .token, .lnurlPay, .lightningAddress, .merchantCode]
    let supportedTypes: [InputView.InputType]
    
    var prioritized: [InputView.InputType] {
        allTypes.sorted { a, b in
            supportedTypes.contains(a) && !supportedTypes.contains(b)
        }
    }
    
    func labelForType(_ type: InputView.InputType) -> String {
        var label: String
        switch type {
            case .bolt11Invoice:     label = String(localized: "Invoice")
            case .bolt12Offer:       label = String(localized: "Offer")
            case .creq:              label = String(localized: "Request")
            case .publicKey:         label = String(localized: "Public Key")
            case .token:             label = String(localized: "Token")
            case .lnurlPay:          label = String(localized: "LNURL-pay")
            case .lightningAddress:  label = String(localized: "Lightning Address")
            case .merchantCode:      label = String(localized: "Merchant QR")
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
