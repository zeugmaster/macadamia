
import Foundation

extension String {
    func decodeBase64UrlSafe() -> String? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Check if padding is needed
        let mod4 = base64.count % 4
        if mod4 != 0 {
            base64 += String(repeating: "=", count: 4 - mod4)
        }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        let string = String(data: data, encoding: .ascii)
        return string
    }

    func encodeBase64UrlSafe(removePadding: Bool = false) -> String {
        let base64Encoded = self.data(using: .ascii)?.base64EncodedString() ?? ""
        var urlSafeBase64 = base64Encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        if removePadding {
            urlSafeBase64 = urlSafeBase64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }

        return urlSafeBase64
    }
}



