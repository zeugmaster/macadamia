import CoreImage.CIFilterBuiltins
import SwiftUI
import URKit
import URUI

/// View that displays either a static or animated QR code
struct QRView: View {
    let string: String?
    let maxStaticLength = 600
    
    init(string: String?) {
        self.string = string
        
        print("called the QRView initializer")
    }
    
    var body: some View {
        Group {
            if let string {
                if string.count > maxStaticLength {
                    AnimatedQRView(string: string)
                } else {
                    StaticQRView(string: string)
                }
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 150)
                    .foregroundColor(Color.gray.opacity(0.3))
            }
        }.id(string) // forces reload whem token string changes between versions
    }
}

/// A view that displays a static QR code
struct StaticQRView: View {
    let string: String
    
    @State private var image: UIImage? = nil
    
    private let qrGenerator = QRCodeGenerator()
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6.0))
            } else {
                Text("Failed to generate QR Code")
            }
        }
        .task {
            self.image = await qrGenerator.generateQRCode(from: string)
        }
    }
}

struct AnimatedQRView: View {
    let string: String
    
    @StateObject private var urDisplayState: URDisplayState
    
    init(string: String) {
        self.string = string
        
        do {
            guard let strData = string.data(using: .utf8) else {
                _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: UR.dummy,
                                                                           maxFragmentLen: 200))
                return
            }

            let ur = try UR(type: "bytes", cbor: strData.cbor)
            _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur,
                                                                       maxFragmentLen: 200))
        } catch {
            print("Error creating UR: \(error.localizedDescription)")
            // Create a dummy URDisplayState as a fallback
            _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: UR.dummy,
                                                                       maxFragmentLen: 200))
        }
    }
    
    var body: some View {
        ZStack {
            Color.white
            URQRCode(data: .constant(urDisplayState.part), foregroundColor: Color.black, backgroundColor: Color.white)
                .onAppear {
                    urDisplayState.run()
                }
                .onDisappear {
                    urDisplayState.stop()
                }
                .padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6.0))
    }
}

extension UR {
    static var dummy: UR {
        do {
            return try UR(type: "bytes", cbor: Data(repeating: 0, count: 100).cbor)
        } catch {
            fatalError("Failed to create dummy UR: \(error)")
        }
    }
}

/// A manager class for QR code generation that handles errors and performs operations asynchronously
final class QRCodeGenerator:Sendable {
    /// Generate QR code asynchronously
    /// - Parameter string: The string to encode in the QR code
    /// - Returns: Optional UIImage if generation succeeds
    func generateQRCode(from string: String) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let _ = self else { return nil }
            
            let filter = CIFilter.qrCodeGenerator()
            filter.setValue(Data(string.utf8), forKey: "inputMessage")
            
            guard let qrCodeImage = filter.outputImage else { return nil }
            
            let transformedImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            guard let qrCodeCGImage = CIContext().createCGImage(transformedImage, from: transformedImage.extent) else {
                return nil
            }
            
            return UIImage(cgImage: qrCodeCGImage, scale: 1, orientation: .up)
        }.value
    }
}

#Preview {
    VStack {
        QRView(string: nil)
            .frame(height: 200)
        
        QRView(string: "https://example.com")
            .frame(height: 200)
        
        QRView(string: "a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string a very long string ")
            .frame(height: 200)
            .padding(40)
    }
}
