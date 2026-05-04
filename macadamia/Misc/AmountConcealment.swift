import Foundation

enum AmountConcealment {
    static let appGroupID = "group.com.cypherbase.macadamia"
    static let userDefaultsKey = "ConcealAmounts"

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func concealedString(for text: String) -> String {
        var sensitiveRunLength = 0
        var output = ""

        func flushSensitiveRun() -> String {
            guard sensitiveRunLength > 0 else { return "" }
            let starCount = max(1, sensitiveRunLength + Int.random(in: -1...1))
            sensitiveRunLength = 0
            return String(repeating: "*", count: starCount)
        }

        for scalar in text.unicodeScalars {
            if isSensitiveAmountScalar(scalar) {
                sensitiveRunLength += 1
            } else {
                output.append(flushSensitiveRun())
                output.unicodeScalars.append(scalar)
            }
        }

        output.append(flushSensitiveRun())
        return output
    }

    static func randomDigitString(matching text: String) -> String {
        var output = ""

        for scalar in text.unicodeScalars {
            if scalar == "*" || isSensitiveAmountScalar(scalar) {
                output.append(String(Int.random(in: 0...9)))
            } else {
                output.unicodeScalars.append(scalar)
            }
        }

        return output
    }

    private static func isSensitiveAmountScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.decimalDigits.contains(scalar) || scalar == "." || scalar == ","
    }
}
