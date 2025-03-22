//
//  TokenShareView.swift
//  macadamia
//
//  Created by zm on 20.11.24.
//

import SwiftUI
import CashuSwift

struct TokenShareView: View {
    var token: CashuSwift.Token
    
    @State private var preferredTokenVersion: CashuSwift.TokenVersion = .V4
    
    @State private var isCopied = false
    
    var tokenString: String {
        do {
            return try token.serialize(to: preferredTokenVersion)
        } catch {
            return "Failed token serialization"
        }
    }
    
    var body: some View {
        Section {
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
            
            TokenText(text: tokenString)
                .frame(idealHeight: 70)
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
        Section {
            QRView(string: tokenString)
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
