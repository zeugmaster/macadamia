@testable import macadamia
import PrettySwiftQR
import SwiftUI
import XCTest

final class QRScannerTests: XCTestCase {
    @MainActor
    private func host(scanner: PrettySwiftQR.QRScanner,
                      onResult: @escaping (String) -> macadamia.QRScanner.ResultValidation) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = UIHostingController(rootView: macadamia.QRScanner(scanner: scanner, onResult: onResult))
        window.makeKeyAndVisible()
        return window
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for scanner", file: file, line: line)
    }

    @MainActor
    func testInvalidTextCanBeScannedAgainAfterRetry() async throws {
        let source = ManualCodeSource()
        let scanner = PrettySwiftQR.QRScanner(source: source)
        var results: [String] = []
        let window = host(scanner: scanner) { string in
            results.append(string)
            return results.count == 1 ? .retryAfter(0.15) : .valid
        }
        defer { window.isHidden = true; window.rootViewController = nil }

        try await waitUntil { scanner.state == .scanning }
        source.send("test-payment-request")
        try await waitUntil { results.count == 1 }
        XCTAssertEqual(scanner.state, .completed(.text("test-payment-request")))
        source.send("ignored-while-retrying")
        try await waitUntil { scanner.state == .scanning }
        source.send("test-payment-request")
        try await waitUntil { results.count == 2 }
        XCTAssertEqual(results, ["test-payment-request", "test-payment-request"])

        source.send("ignored-after-success")
        try await waitUntil { scanner.receivedCodeCount == 4 }
        XCTAssertEqual(results.count, 2)
        await scanner.stop()
    }

    @MainActor
    func testAnimatedURDeliversOriginalUTF8Text() async throws {
        let source = ManualCodeSource()
        let scanner = PrettySwiftQR.QRScanner(source: source)
        let text = String(repeating: "cashu-token-🥜", count: 80)
        let encoder = UREncoder(UR(bytes: Data(text.utf8)), maxFragmentLen: 200)
        var results: [String] = []
        let window = host(scanner: scanner) { string in
            results.append(string)
            return .valid
        }
        defer { window.isHidden = true; window.rootViewController = nil }

        try await waitUntil { scanner.state == .scanning }
        source.send(encoder.nextPart().uppercased())
        try await waitUntil { scanner.progress != nil }
        XCTAssertGreaterThan(scanner.progress?.fraction ?? 0, 0)
        XCTAssertLessThan(scanner.progress?.fraction ?? 1, 1)

        for _ in 1..<encoder.seqLen {
            source.send(encoder.nextPart().uppercased())
        }
        try await waitUntil { results.count == 1 }
        XCTAssertEqual(results, [text])
        XCTAssertEqual(scanner.progress?.fraction, 1)
        await scanner.stop()
    }

    @MainActor
    func testNonUTF8URResetsAndAllowsNextTextScan() async throws {
        let source = ManualCodeSource()
        let scanner = PrettySwiftQR.QRScanner(source: source)
        var results: [String] = []
        let window = host(scanner: scanner) { string in
            results.append(string)
            return .valid
        }
        defer { window.isHidden = true; window.rootViewController = nil }

        try await waitUntil { scanner.state == .scanning }
        source.send(UR(bytes: Data([0xff, 0xfe])).qrString)
        try await waitUntil { scanner.receivedCodeCount == 1 && scanner.state == .scanning }
        XCTAssertTrue(results.isEmpty)

        source.send("https://example.com")
        try await waitUntil { results.count == 1 }
        XCTAssertEqual(results, ["https://example.com"])
        await scanner.stop()
    }
}
