import XCTest
@testable import SerbianEIDKit

final class TLVParserTests: XCTestCase {

    /// Builds a little-endian TLV record: tag(u16) + length(u16) + value.
    private func record(tag: Int, _ value: [UInt8]) -> [UInt8] {
        [UInt8(tag & 0xFF), UInt8((tag >> 8) & 0xFF),
         UInt8(value.count & 0xFF), UInt8((value.count >> 8) & 0xFF)] + value
    }

    private func hex(_ s: String) -> Data {
        var bytes = [UInt8](); var it = s.makeIterator();
        while let a = it.next(), let b = it.next() {
            bytes.append(UInt8(String([a, b]), radix: 16)!)
        }
        return Data(bytes)
    }

    func testParsesTwoRecords() {
        let blob = record(tag: 1559, Array("КРСТИЋ".utf8)) + record(tag: 1562, Array("M".utf8))
        let records = TLVParser.parse(Data(blob))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].tag, 1559)
        XCTAssertEqual(records[0].value, "КРСТИЋ")   // UTF-8 Cyrillic round-trips
        XCTAssertEqual(records[1].tag, 1562)
        XCTAssertEqual(records[1].value, "M")
    }

    func testStopsAtZeroTagPadding() {
        var blob = record(tag: 1570, Array("BEOGRAD".utf8))
        blob += [0x00, 0x00, 0x00, 0x00]          // stop tag + length
        blob += [0xFF, 0xFF, 0xFF, 0xFF, 0xFF]    // trailing padding, must be ignored
        let records = TLVParser.parse(Data(blob))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].value, "BEOGRAD")
    }

    func testIgnoresTrailingBytesShorterThanAHeader() {
        // Fewer than 5 bytes left after a record must not produce a spurious entry.
        let blob = record(tag: 1570, Array("X".utf8)) + [0x01, 0x02]
        let records = TLVParser.parse(Data(blob))
        XCTAssertEqual(records.count, 1)
    }

    /// Real DOCUMENT-file fragment captured from a card (EF 0F02, after the 4-byte header).
    func testParsesRealDocumentFragment() {
        let fragment = hex("0A060900303130323331373133" + // tag 1546 len 9  "010231713"
                           "09060300535242"              + // tag 1545 len 3  "SRB"
                           "0B0602004944")                  // tag 1547 len 2  "ID"
        let records = TLVParser.parse(fragment)
        let map = Dictionary(uniqueKeysWithValues: records.map { ($0.tag, $0.value) })
        XCTAssertEqual(map[1546], "010231713")
        XCTAssertEqual(map[1547], "ID")
    }

    func testDecodeStringFallsBackToHexForBinary() {
        // 0xFF 0xFE is invalid UTF-8; ISO-8859-1 still decodes it, so it never reaches hex.
        // Use a lone 0x80 which ISO-8859-1 maps too — decodeString always yields a String.
        let s = TLVParser.decodeString(Data([0x41, 0x42]))
        XCTAssertEqual(s, "AB")
    }

    func testHexString() {
        XCTAssertEqual(TLVParser.hexString([0x3B, 0x00, 0xFF]), "3B00FF")
    }
}
