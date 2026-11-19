//
//  TokenShareView.swift
//  macadamia
//
//  Created by zm on 20.11.24.
//

import SwiftUI
import CashuSwift

struct TokenShareView: View {
    let token: CashuSwift.Token

    @State private var preferredTokenVersion: CashuSwift.TokenVersion = .V4
    @State private var isCopied = false
    @State private var tokenString = ""

    /// V3 tokens carry no top-level `unit` field (NUT-00) — they're
    /// implicitly sat. Anything else can only legitimately serialize as V4,
    /// so we hide the version picker and stick to V4 in that case.
    private var supportsV3: Bool {
        Currency.Unit(code: token.unit) == .sat
    }

    init(token: CashuSwift.Token) {
        self.token = token
        let string = (try? token.serialize(to: .V4)) ?? ""
        self._tokenString = State(initialValue: string)
    }

    var body: some View {
        Section {
            if supportsV3 {
                HStack {
                    Text("Version: ")
                    Spacer()
                    Picker("", selection: $preferredTokenVersion) {
                        Text("V3").tag(CashuSwift.TokenVersion.V3)
                        Text("V4").tag(CashuSwift.TokenVersion.V4)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            TokenText(text: tokenString)
                .frame(idealHeight: 90)
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 14))
            Button {
                copyToClipboard()
            } label: {
                HStack {
                    if isCopied {
                        Text("Copied!")
                            .transition(.opacity)
                    } else {
                        Text("Copy to clipboard")
                            .transition(.opacity)
                    }
                    Spacer()
                    Image(systemName: "list.clipboard")
                }
            }
            
            ShareLink(item: URL(string: "cashu:" + tokenString)!) {
                HStack {
                    Text("Share")
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onChange(of: preferredTokenVersion) { oldValue, newValue in
            tokenString = (try? token.serialize(to: newValue)) ?? ""
        }
        
        Section {
            QRView(string: tokenString)
                .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
                .id(tokenString)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Text("Share via QR code")
        }
    }
    
    func copyToClipboard() {
        UIPasteboard.general.string = tokenString
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#if DEBUG
private struct TokenSharePreview: View {
    private let token: CashuSwift.Token

    init(proofCount: Int, unit: String = "sat") {
        // Synthetic proofs with valid hex fields for both V3 and V4 serialization.
        // No mint connection or wallet state is needed by these previews.
        let proofs = (0..<proofCount).map { index in
            CashuSwift.Proof(
                keysetID: "009a1f293253e41e",
                amount: 1 << index,
                secret: String(format: "%064x", index + 1),
                C: "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
        }
        token = CashuSwift.Token(proofs: ["https://mint.example.com": proofs],
                                 unit: unit, memo: "Preview token")
    }

    var body: some View {
        NavigationStack {
            Form {
                TokenShareView(token: token)
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Static QR") {
    TokenSharePreview(proofCount: 1)
}

#Preview("Animated QR") {
    TokenSharePreview(proofCount: 8)
}

#Preview("Non-sat token") {
    TokenSharePreview(proofCount: 1, unit: "usd")
}
#endif
