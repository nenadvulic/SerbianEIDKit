import XCTest
@testable import SerbianEIDKit

final class SerializationTests: XCTestCase {

    private func sampleDocument() -> EidDocument {
        EidDocument(
            fields: [.surname: "КРСТИЋ", .givenName: "АЛЕКСАНДАР", .personalNumber: "1905989710083"],
            unknownFields: [1545: "SRB"],
            variant: .citizen
        )
    }

    func testEncodeProducesReadableKeys() throws {
        let data = try JSONEncoder().encode(sampleDocument())
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"surname\""))
        XCTAssertTrue(json.contains("\"variant\""))
        XCTAssertTrue(json.contains("\"1545\""))
        XCTAssertFalse(json.contains("1559"))   // raw tag numbers are not used as keys
    }

    func testRoundTrip() throws {
        let original = sampleDocument()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EidDocument.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFieldKeyRoundTrip() {
        for field in EidField.allCases {
            XCTAssertEqual(EidField(key: field.key), field)
        }
        XCTAssertNil(EidField(key: "nope"))
    }

    func testDecodeToleratesMissingSections() throws {
        let json = #"{"fields":{"surname":"X"}}"#.data(using: .utf8)!
        let doc = try JSONDecoder().decode(EidDocument.self, from: json)
        XCTAssertEqual(doc[.surname], "X")
        XCTAssertTrue(doc.unknownFields.isEmpty)
        XCTAssertNil(doc.variant)
    }
}
