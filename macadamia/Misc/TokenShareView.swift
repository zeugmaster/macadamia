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
    
    init(token: CashuSwift.Token) {
        self.token = token
        let string = (try? token.serialize(to: .V4)) ?? ""
        self._tokenString = State(initialValue: string)
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
                .listRowBackground(Color.clear)
                .id(tokenString)
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
