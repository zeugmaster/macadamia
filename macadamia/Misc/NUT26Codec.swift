import Foundation
import CashuSwift
import NostrSDK

// MARK: - NUT-26 Payment Request Bech32m Codec
// https://github.com/cashubtc/nuts/blob/main/26.md

enum NUT26 {

    enum CodecError: Error {
        case invalidPrefix
        case invalidBech32m
        case invalidTLV(String)
        case nostrPubkeyDecoding(String)
        case nostrPubkeyEncoding(String)
    }

    // MARK: - Public API

    /// Encodes a PaymentRequest to NUT-26 Bech32m format. Output is uppercase for QR code compatibility.
    static func encode(_ request: CashuSwift.PaymentRequest) throws -> String {
        let tlvData = try encodeTLV(request)
        return try bech32mEncode(hrp: "creqb", data: tlvData).uppercased()
    }

    /// Decodes a NUT-26 Bech32m-encoded payment request string (case-insensitive).
    static func decode(_ string: String) throws -> CashuSwift.PaymentRequest {
        guard string.lowercased().hasPrefix("creqb") else {
            throw CodecError.invalidPrefix
        }
        let (hrp, data) = try bech32mDecode(string)
        guard hrp == "creqb" else {
            throw CodecError.invalidPrefix
        }
        return try decodeTLV(data)
    }

    // MARK: - Bech32m (BIP-350)
    // Identical to Bech32 except the checksum constant is 0x2bc830a3 instead of 1.

    private static let charset: [Character] = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let charsetMap: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (i, c) in charset.enumerated() { map[c] = UInt8(i) }
        return map
    }()

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i in 0..<5 where ((top >> i) & 1) != 0 { chk ^= gen[i] }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var r: [UInt8] = []
        for c in hrp.unicodeScalars { r.append(UInt8(c.value >> 5)) }
        r.append(0)
        for c in hrp.unicodeScalars { r.append(UInt8(c.value & 0x1f)) }
        return r
    }

    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ 0x2bc830a3
        return (0..<6).map { UInt8((mod >> (5 * (5 - $0))) & 31) }
    }

    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 0x2bc830a3
    }

    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        for v in data {
            acc = (acc << fromBits) | Int(v)
            bits += fromBits
            while bits >= toBits { bits -= toBits; result.append(UInt8((acc >> bits) & maxv)) }
        }
        if pad {
            if bits > 0 { result.append(UInt8((acc << (toBits - bits)) & maxv)) }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        return result
    }

    static func bech32mEncode(hrp: String, data: Data) throws -> String {
        guard let fiveBit = convertBits(data: Array(data), fromBits: 8, toBits: 5, pad: true) else {
            throw CodecError.invalidBech32m
        }
        let combined = fiveBit + createChecksum(hrp: hrp, data: fiveBit)
        return hrp + "1" + combined.map { String(charset[Int($0)]) }.joined()
    }

    static func bech32mDecode(_ string: String) throws -> (hrp: String, data: Data) {
        let lower = string.lowercased()
        guard let sep = lower.lastIndex(of: "1") else { throw CodecError.invalidBech32m }
        let hrp = String(lower[lower.startIndex..<sep])
        let dataPart = String(lower[lower.index(after: sep)...])
        var decoded: [UInt8] = []
        for c in dataPart {
            guard let v = charsetMap[c] else { throw CodecError.invalidBech32m }
            decoded.append(v)
        }
        guard verifyChecksum(hrp: hrp, data: decoded) else { throw CodecError.invalidBech32m }
        guard let eightBit = convertBits(data: Array(decoded.dropLast(6)), fromBits: 5, toBits: 8, pad: false) else {
            throw CodecError.invalidBech32m
        }
        return (hrp, Data(eightBit))
    }

    // MARK: - TLV Helpers
    // Each TLV field: type (1 byte) | length (2 bytes big-endian) | value

    private static func writeTLV(tag: UInt8, value: Data) -> Data {
        var d = Data()
        d.append(tag)
        d.append(UInt8(value.count >> 8))
        d.append(UInt8(value.count & 0xff))
        d.append(contentsOf: value)
        return d
    }

    private static func readTLVFields(_ data: Data) throws -> [(tag: UInt8, value: Data)] {
        var fields: [(UInt8, Data)] = []
        var i = data.startIndex
        while i < data.endIndex {
            guard data.distance(from: i, to: data.endIndex) >= 3 else {
                throw CodecError.invalidTLV("Truncated TLV header at offset \(data.distance(from: data.startIndex, to: i))")
            }
            let tag = data[i]
            let length = Int(data[data.index(i, offsetBy: 1)]) << 8 | Int(data[data.index(i, offsetBy: 2)])
            i = data.index(i, offsetBy: 3)
            guard data.distance(from: i, to: data.endIndex) >= length else {
                throw CodecError.invalidTLV("Truncated TLV value for tag 0x\(String(tag, radix: 16))")
            }
            fields.append((tag, data[i..<data.index(i, offsetBy: length)]))
            i = data.index(i, offsetBy: length)
        }
        return fields
    }

    // MARK: - Tag Tuple Encoding/Decoding
    // A single 0x03 TLV field encodes one tag tuple: [key, value1, value2, ...]
    // Wire format: keyLen(1) | key | valLen(1) | val | valLen(1) | val | ...

    private static func encodeTagTuple(_ tuple: [String]) -> Data {
        var d = Data()
        guard !tuple.isEmpty else { return d }
        let keyBytes = Data(tuple[0].utf8)
        d.append(UInt8(keyBytes.count))
        d.append(contentsOf: keyBytes)
        for value in tuple.dropFirst() {
            let valBytes = Data(value.utf8)
            d.append(UInt8(valBytes.count))
            d.append(contentsOf: valBytes)
        }
        return d
    }

    private static func decodeTagTupleField(_ data: Data) -> [String]? {
        var i = data.startIndex
        guard i < data.endIndex else { return nil }
        let keyLen = Int(data[i])
        i = data.index(after: i)
        guard data.distance(from: i, to: data.endIndex) >= keyLen else { return nil }
        guard let key = String(bytes: data[i..<data.index(i, offsetBy: keyLen)], encoding: .utf8) else { return nil }
        i = data.index(i, offsetBy: keyLen)
        var tuple = [key]
        while i < data.endIndex {
            let valLen = Int(data[i])
            i = data.index(after: i)
            guard valLen > 0, data.distance(from: i, to: data.endIndex) >= valLen else { break }
            guard let val = String(bytes: data[i..<data.index(i, offsetBy: valLen)], encoding: .utf8) else { break }
            tuple.append(val)
            i = data.index(i, offsetBy: valLen)
        }
        return tuple
    }

    // MARK: - Nostr Target Encoding/Decoding

    private static func nostrTargetToBytesAndRelays(_ target: String) throws -> (pubkeyBytes: Data, relays: [String]) {
        if target.lowercased().hasPrefix("nprofile") {
            struct Coder: MetadataCoding {}
            let metadata = try Coder().decodedMetadata(from: target)
            guard let pubkeyHex = metadata.pubkey, let pubkey = PublicKey(hex: pubkeyHex) else {
                throw CodecError.nostrPubkeyDecoding("Could not decode pubkey from nprofile")
            }
            return (pubkey.dataRepresentation, metadata.relays ?? [])
        } else {
            guard let pubkey = PublicKey(npub: target) else {
                throw CodecError.nostrPubkeyDecoding("Could not decode npub: \(target)")
            }
            return (pubkey.dataRepresentation, [])
        }
    }

    private static func bytesToNostrTarget(_ bytes: Data, relays: [String]) throws -> String {
        guard let pubkey = PublicKey(dataRepresentation: bytes) else {
            throw CodecError.nostrPubkeyEncoding("Could not create public key from \(bytes.count) bytes")
        }
        guard !relays.isEmpty else { return pubkey.npub }
        struct Coder: MetadataCoding {}
        return try Coder().encodedIdentifier(with: Metadata(pubkey: pubkey.hex, relays: relays), identifierType: .profile)
    }

    // MARK: - Transport Sub-TLV (Tag 0x07)

    private static func encodeTransport(_ transport: CashuSwift.Transport) throws -> Data {
        var result = Data()

        let kind: UInt8
        switch transport.type {
        case CashuSwift.Transport.TransportType.nostr:    kind = 0x00
        case CashuSwift.Transport.TransportType.httpPost: kind = 0x01
        default:                                          kind = 0x01
        }
        result.append(contentsOf: writeTLV(tag: 0x01, value: Data([kind])))

        if kind == 0x00 {
            let (pubkeyBytes, relayURLs) = try nostrTargetToBytesAndRelays(transport.target)
            result.append(contentsOf: writeTLV(tag: 0x02, value: pubkeyBytes))
            for relay in relayURLs {
                result.append(contentsOf: writeTLV(tag: 0x03, value: encodeTagTuple(["r", relay])))
            }
            if let tags = transport.tags {
                for tag in tags {
                    result.append(contentsOf: writeTLV(tag: 0x03, value: encodeTagTuple(tag)))
                }
            }
        } else {
            result.append(contentsOf: writeTLV(tag: 0x02, value: Data(transport.target.utf8)))
            if let tags = transport.tags {
                for tag in tags {
                    result.append(contentsOf: writeTLV(tag: 0x03, value: encodeTagTuple(tag)))
                }
            }
        }

        return result
    }

    private static func decodeTransport(_ data: Data) throws -> CashuSwift.Transport {
        let fields = try readTLVFields(data)

        var kind: UInt8?
        var targetData: Data?
        var tagTuples: [[String]] = []

        for field in fields {
            switch field.tag {
            case 0x01: kind = field.value.first
            case 0x02: targetData = field.value
            case 0x03:
                if let tuple = decodeTagTupleField(field.value) { tagTuples.append(tuple) }
            default: break
            }
        }

        guard let k = kind, let tData = targetData else {
            throw CodecError.invalidTLV("Transport missing kind or target")
        }

        let transportType: String
        let targetString: String

        switch k {
        case 0x00:
            transportType = CashuSwift.Transport.TransportType.nostr
            let relays = tagTuples.filter { $0.first == "r" }.flatMap { Array($0.dropFirst()) }
            targetString = try bytesToNostrTarget(tData, relays: relays)
            tagTuples = tagTuples.filter { $0.first != "r" }
        case 0x01:
            transportType = CashuSwift.Transport.TransportType.httpPost
            guard let url = String(bytes: tData, encoding: .utf8) else {
                throw CodecError.invalidTLV("Invalid UTF-8 in transport target URL")
            }
            targetString = url
        default:
            throw CodecError.invalidTLV("Unknown transport kind: \(k)")
        }

        return CashuSwift.Transport(type: transportType, target: targetString, tags: tagTuples.isEmpty ? nil : tagTuples)
    }

    // MARK: - NUT-10 Sub-TLV (Tag 0x08)

    private static let nut10KindEncode: [String: UInt8] = ["P2PK": 0x00, "HTLC": 0x01]
    private static let nut10KindDecode: [UInt8: String] = [0x00: "P2PK", 0x01: "HTLC"]

    private static func encodeNUT10(_ option: CashuSwift.NUT10Option) -> Data {
        var result = Data()
        result.append(contentsOf: writeTLV(tag: 0x01, value: Data([nut10KindEncode[option.kind] ?? 0x00])))
        result.append(contentsOf: writeTLV(tag: 0x02, value: Data(option.data.utf8)))
        if let tags = option.tags {
            for tag in tags {
                result.append(contentsOf: writeTLV(tag: 0x03, value: encodeTagTuple(tag)))
            }
        }
        return result
    }

    private static func decodeNUT10(_ data: Data) throws -> CashuSwift.NUT10Option {
        let fields = try readTLVFields(data)
        var kind: UInt8?
        var optionData: String?
        var tagTuples: [[String]] = []
        for field in fields {
            switch field.tag {
            case 0x01: kind = field.value.first
            case 0x02: optionData = String(bytes: field.value, encoding: .utf8)
            case 0x03:
                if let tuple = decodeTagTupleField(field.value) { tagTuples.append(tuple) }
            default: break
            }
        }
        guard let k = kind, let d = optionData else {
            throw CodecError.invalidTLV("NUT-10 option missing kind or data")
        }
        return CashuSwift.NUT10Option(
            kind: nut10KindDecode[k] ?? "P2PK",
            data: d,
            tags: tagTuples.isEmpty ? nil : tagTuples
        )
    }

    // MARK: - Top-Level TLV Encode

    static func encodeTLV(_ request: CashuSwift.PaymentRequest) throws -> Data {
        var result = Data()

        if let id = request.paymentId {
            result.append(contentsOf: writeTLV(tag: 0x01, value: Data(id.utf8)))
        }
        if let amount = request.amount {
            var be = UInt64(amount).bigEndian
            result.append(contentsOf: writeTLV(tag: 0x02, value: Data(bytes: &be, count: 8)))
        }
        if let unit = request.unit {
            let unitData: Data = unit == "sat" ? Data([0x00]) : Data(unit.utf8)
            result.append(contentsOf: writeTLV(tag: 0x03, value: unitData))
        }
        if let singleUse = request.singleUse {
            result.append(contentsOf: writeTLV(tag: 0x04, value: Data([singleUse ? 0x01 : 0x00])))
        }
        for mint in request.mints ?? [] {
            result.append(contentsOf: writeTLV(tag: 0x05, value: Data(mint.utf8)))
        }
        if let desc = request.description {
            result.append(contentsOf: writeTLV(tag: 0x06, value: Data(desc.utf8)))
        }
        for transport in request.transports ?? [] {
            result.append(contentsOf: writeTLV(tag: 0x07, value: try encodeTransport(transport)))
        }
        if let nut10 = request.lockingCondition {
            result.append(contentsOf: writeTLV(tag: 0x08, value: encodeNUT10(nut10)))
        }

        return result
    }

    // MARK: - Top-Level TLV Decode

    static func decodeTLV(_ data: Data) throws -> CashuSwift.PaymentRequest {
        let fields = try readTLVFields(data)

        var paymentId: String?
        var amount: Int?
        var unit: String?
        var singleUse: Bool?
        var mints: [String] = []
        var description: String?
        var transports: [CashuSwift.Transport] = []
        var lockingCondition: CashuSwift.NUT10Option?

        for field in fields {
            switch field.tag {
            case 0x01:
                paymentId = String(bytes: field.value, encoding: .utf8)
            case 0x02:
                guard field.value.count == 8 else { break }
                amount = Int(field.value.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
            case 0x03:
                if field.value.count == 1 && field.value[field.value.startIndex] == 0x00 {
                    unit = "sat"
                } else {
                    unit = String(bytes: field.value, encoding: .utf8)
                }
            case 0x04:
                singleUse = field.value.first == 0x01
            case 0x05:
                if let mint = String(bytes: field.value, encoding: .utf8) { mints.append(mint) }
            case 0x06:
                description = String(bytes: field.value, encoding: .utf8)
            case 0x07:
                transports.append(try decodeTransport(field.value))
            case 0x08:
                lockingCondition = try decodeNUT10(field.value)
            default:
                break // Unknown tags MUST be ignored per spec
            }
        }

        return CashuSwift.PaymentRequest(
            paymentId: paymentId,
            amount: amount,
            unit: unit,
            singleUse: singleUse,
            mints: mints.isEmpty ? nil : mints,
            description: description,
            transports: transports.isEmpty ? nil : transports,
            lockingCondition: lockingCondition
        )
    }
}

// MARK: - Dual-format parser

/// Parses a payment request string in either NUT-18 (creqA) or NUT-26 (creqb) format.
func parsePaymentRequest(_ string: String) throws -> CashuSwift.PaymentRequest {
    if string.lowercased().hasPrefix("creqb") {
        return try NUT26.decode(string)
    }
    return try CashuSwift.PaymentRequest(encodedRequest: string)
}
