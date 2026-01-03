//
//  CopyButton.swift
//  macadamia
//
//  Created by zm on 03.01.26.
//

import SwiftUI

struct CopyButton: View {
    @Binding var content: String
    
    @State private var copied = false
    
    var body: some View {
        Button {
            if copied { return }
            UIPasteboard.general.string = content
            withAnimation {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    copied = false
                }
            }
        } label: {
            HStack {
                Text("Copy")
                Spacer()
                Image(systemName: copied ? "list.clipboard.fill" : "clipboard")
            }
//            .fontWeight(.medium)
        }
    }
}

#Preview {
    List {
        CopyButton(content: .constant("this goes to the clipboard"))
    }
}
