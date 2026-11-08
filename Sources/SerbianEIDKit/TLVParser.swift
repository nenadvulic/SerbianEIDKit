//
//  TLVParser.swift
//  SerbianEIDKit
//
//  Parser for the proprietary TLV format used inside each elementary file.
//

import Foundation

/// Parser for the eID's proprietary little-endian TLV encoding.
///
/// Each record is laid out as:
///
///     tag   : UInt16 (little-endian)
///     length: UInt16 (little-endian)
///     value : <length> bytes
///
/// Records are concatenated until a tag of `0` is reached, after which the rest of
/// the file is padding. This mirrors the decoding logic of the official reader app.
public enum TLVParser {

    /// A single decoded record: its numeric tag and its string value.
    public typealias Record = (tag: Int, value: String)

    /// Parses a decrypted elementary-file payload into a list of records.
    ///
    /// - Parameter bytes: the file payload, with any elementary-file prefix already removed.
    /// - Returns: the decoded records, in file order.
    public static func parse(_ bytes: Data) -> [Record] {
        var out: [Record] = []
        var i = bytes.startIndex
        let end = bytes.endIndex

        func readUInt16() -> Int {
            let low = Int(bytes[i])
            let high = Int(bytes[i + 1])
            i += 2
            return low | (high << 8)
        }

        // The original loop strictly requires more than 4 bytes left (a full tag + length).
        while bytes.distance(from: i, to: end) > 4 {
            let tag = readUInt16()
            let length = readUInt16()
            if tag == 0 { break }   // real end of data: the rest is padding
            guard length >= 0, bytes.distance(from: i, to: end) >= length else { break }
            let value = bytes.subdata(in: i..<bytes.index(i, offsetBy: length))
            i = bytes.index(i, offsetBy: length)
            out.append((tag, decodeString(value)))
        }
        return out
    }

    /// Decodes a value as UTF-8, falling back to ISO-8859-1, then to a hex string.
    /// Matches the official app's `Utils.bytes2UTF8String` behaviour.
    public static func decodeString(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return hexString(Array(data))
    }

    /// Formats bytes as an uppercase hex string (no separators).
    public static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
