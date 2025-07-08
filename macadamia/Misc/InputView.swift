import SwiftUI
import AVFoundation

struct InputView: View {
    
    enum InputType {
        case bolt11Invoice, bolt12Offer, token, creq, publicKey
    }
    
    let onResult: (String) -> Void
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    
    var body: some View {
        Group {
            if cameraPermissionStatus == .authorized {
                QRScanner { string in
                    onResult(string)
                }
                .frame(minHeight: 300, maxHeight: 400)
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
    
    @MainActor
    private func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        logger.info("user pasted string \(pasteString.prefix(20) + (pasteString.count < 20 ? "" : "..."))")
        onResult(pasteString)
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
    
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}
