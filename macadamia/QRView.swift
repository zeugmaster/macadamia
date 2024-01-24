//
//  QRView.swift
//  macadamia
//
//  Created by zeugmaster on 14.12.23.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.setValue(Data(string.utf8), forKey: "inputMessage")

    let colorFilter = CIFilter.falseColor()
    colorFilter.setValue(filter.outputImage, forKey: "inputImage")
    colorFilter.setDefaults()
    colorFilter.setValue(CIColor.white, forKey: "inputColor0") // QR code color (white)
    colorFilter.setValue(CIColor.clear, forKey: "inputColor1") // Background color (transparent)

    if let coloredQRCodeImage = colorFilter.outputImage {
        let transformedImage = coloredQRCodeImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) // Scale up to improve quality
        if let qrCodeCGImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            return UIImage(cgImage: qrCodeCGImage, scale: 1, orientation: .up)
        }
    }

    return nil
}


struct QRCodeView: View {
    let qrCode: UIImage?

    var body: some View {
        if let qrCode = qrCode {
            Image(uiImage: qrCode)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                //.frame(width: 200, height: 200)
        } else {
            Text("Failed to generate QR Code")
        }
    }
}

