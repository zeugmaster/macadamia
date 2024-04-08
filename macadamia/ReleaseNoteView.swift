//
//  ReleaseNoteView.swift
//  macadamia
//
//  Created by zm on 08.04.24.
//

import SwiftUI
import WebKit
import MarkdownUI
import CryptoKit
import secp256k1

struct ReleaseNote {
    ///Loads the release notes from file
    static func stringFromFile() -> String {
        guard let filePath = Bundle.main.path(forResource: "release-notes", ofType: "md") else {
            return "Markdown file not found."
        }
        do {
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            return contents
        } catch {
            return "Error reading markdown file: \(error)"
        }
    }
    
    ///Provides the first 16 characters of a hash over the bundle's release notes
    static func hashString() -> String? {
        guard let input = stringFromFile().data(using: .utf8) else {
            return nil
        }
        return String(String(bytes: SHA256.hash(data: input).bytes).prefix(16))
    }
}

struct ReleaseNoteView: View {
    var markdown: String {
        ReleaseNote.stringFromFile()
    }
    
    var body: some View {
        ScrollView {
            Markdown(markdown)
                .markdownTextStyle(\.link, textStyle: {
//                    UnderlineStyle(.single)
                    ForegroundColor(.blue)
                })
                .padding()
            Spacer()
        }
        .toolbar(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ReleaseNoteView()
}
