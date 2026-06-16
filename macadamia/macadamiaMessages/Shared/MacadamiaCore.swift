import Foundation
import SwiftData
import CashuSwift
import OSLog

// MARK: - Shared Logger
let coreLogger = Logger(subsystem: "macadamia Core", category: "Shared")

// MARK: - Array Extensions
extension Array where Element == AppSchemaV1.Proof {
    var sum: Int {
        return self.reduce(0) { $0 + $1.amount }
    }
}
