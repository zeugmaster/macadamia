import CoreImage.CIFilterBuiltins
import SwiftUI
import URKit
import URUI

func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.setValue(Data(string.utf8), forKey: "inputMessage")

    // Removing the false color filter to use the default black & white QR code
    if let qrCodeImage = filter.outputImage {
        let transformedImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) // Scale up to improve quality
        if let qrCodeCGImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            return UIImage(cgImage: qrCodeCGImage, scale: 1, orientation: .up)
        }
    }

    return nil
}

struct StaticQR: View {
    let qrCode: UIImage?

    var body: some View {
        if let qrCode = qrCode {
            Image(uiImage: qrCode)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 6, height: 10)))
            // .frame(width: 200, height: 200)
        } else {
            Text("Failed to generate QR Code")
        }
    }
}

/// View that displays either a static or animated QR code
struct QRView: View {
    let string: String
    @StateObject private var urDisplayState: URDisplayState

    // TODO: needs to accept bytes(string) cbor and json -> cbor in the future
    init(string: String) {
        self.string = string
        let strData = string.data(using: .utf8)!

        // TODO: handle errors, remove hardcoded max frag size
        let ur = try! UR(type: "bytes", cbor: strData.cbor)
        _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur, maxFragmentLen: 200))
    }

    var body: some View {
        if string.count < 650 {
            StaticQR(qrCode: generateQRCode(from: string))
                .clipShape(RoundedRectangle(cornerRadius: 6.0))
        } else {
            ZStack {
                Color(.white)
                URQRCode(data: .constant(urDisplayState.part),
                         foregroundColor: .black,
                         backgroundColor: .white)
                    .onAppear {
                        urDisplayState.framesPerSecond = 8
                        urDisplayState.run()
                    }
                    .onDisappear {
                        urDisplayState.stop()
                    }
                    .padding(10)
            }
        }
    }
}

#Preview {
    QRView(string: "")
}
