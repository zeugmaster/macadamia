import SwiftUI

struct InputView: View {
    
    let onResult: (String) -> Void
    
    var body: some View {
        QRScanner { string in
            onResult(string)
        }
        .frame(minHeight: 300, maxHeight: 400)
        .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
        Button {
            paste()
        } label: {
            HStack {
                Text("Paste from clipboard")
                Spacer()
                Image(systemName: "doc.on.clipboard")
            }
        }
    }
    
    @MainActor
    private func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        logger.info("user pasted string \(pasteString.prefix(20) + (pasteString.count < 20 ? "" : "..."))")
        onResult(pasteString)
    }
}

