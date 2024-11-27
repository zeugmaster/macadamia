//
//  TokenShareView.swift
//  macadamia
//
//  Created by zm on 20.11.24.
//

import SwiftUI

struct TokenShareView: View {
    var tokenString:String
    
    @State private var showingShareSheet = false
    @State private var isCopied = false
    
    var body: some View {
        Section {
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

            Button {
                showingShareSheet = true
            } label: {
                HStack {
                    Text("Share")
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet, content: {
            ShareSheet(items: [tokenString])
        })
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

//#Preview {
//    TokenShareView()
//}
