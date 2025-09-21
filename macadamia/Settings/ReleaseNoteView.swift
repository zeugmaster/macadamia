import CryptoKit
import MarkdownUI
import SwiftUI
import WebKit

enum ReleaseNote {
    /// Loads the release notes from file
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

    /// Provides the first 16 characters of a hash over the bundle's release notes
    static func hashString() -> String? {
        guard let input = stringFromFile().data(using: .utf8) else {
            return nil
        }
        return String(String(bytes: SHA256.hash(data: input).bytes).prefix(16))
    }
}

struct ReleaseNoteView: View {
    var mdWithSubstitutions: String {
        // Fetch version and build numbers
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown Version"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown Build"
        // Replace placeholders with actual values
        var md = ReleaseNote.stringFromFile()
        md = md.replacingOccurrences(of: "{{VERSION}}", with: version)
        md = md.replacingOccurrences(of: "{{BUILD}}", with: build)
        return md
    }

    var body: some View {
        ScrollView {
            Markdown(mdWithSubstitutions)
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
