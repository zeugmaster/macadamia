//
//  QRView.swift
//  macadamia
//
//  Created by Dario Lass on 14.12.23.
//

import SwiftUI

import CoreImage.CIFilterBuiltins

func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.setValue(Data(string.utf8), forKey: "inputMessage")

    let colorInvertFilter = CIFilter.colorInvert()

    if let qrCodeImage = filter.outputImage {
        colorInvertFilter.setValue(qrCodeImage, forKey: kCIInputImageKey)

        if let outputImage = colorInvertFilter.outputImage,
           let qrCodeCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: qrCodeCGImage)
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

