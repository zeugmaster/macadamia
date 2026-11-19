import SwiftUI
import PrettySwiftQR

/// View that displays either a static or animated QR code
struct QRView: View {
    let string: String?
    let maxStaticLength = 600
    
    init(string: String?) {
        self.string = string
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
        }.id(string) // forces reload when token string changes between versions
    }
}

/// A view that displays a static QR code.
struct StaticQRView: View {
    let string: String

    var body: some View {
        StyledQRCodeView(payload: .text(string))
    }
}

struct AnimatedQRView: View {
    let string: String

    var body: some View {
        StyledQRCodeView(payload: .animated(text: string, maxFragmentLength: 200))
    }
}

/// Shared rendering keeps static codes and every animated frame styled alike.
private struct StyledQRCodeView: View {
    let payload: QRPayload

    var body: some View {
        QRCodeView(payload) { error in
            if error != nil {
                Text("Failed to generate QR Code")
            } else {
                ProgressView()
            }
        }
        .qrStyle(.rounded(0.40, inner: 0.40).foreground(.primary).background(.clear))
        .qrFrameRate(10)
        .qrReveal(.none)
        .clipShape(RoundedRectangle(cornerRadius: 6.0))
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
