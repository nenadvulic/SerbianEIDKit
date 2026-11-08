import XCTest
@testable import SerbianEIDKit

final class EidDocumentTests: XCTestCase {

    func testSubscriptReturnsEmptyForMissingField() {
        let doc = EidDocument()
        XCTAssertEqual(doc[.surname], "")
    }

    func testFullNameComposition() {
        let doc = EidDocument(fields: [
            .givenName: "АЛЕКСАНДАР",
            .parentGivenName: "MIODRAG",
            .surname: "КРСТИЋ",
        ])
        XCTAssertEqual(doc.fullName, "АЛЕКСАНДАР MIODRAG КРСТИЋ")
    }

    func testFullNameTrimsMissingMiddlePart() {
        let doc = EidDocument(fields: [.givenName: "АНА", .surname: "ЈОВИЋ"])
        XCTAssertEqual(doc.fullName, "АНА  ЈОВИЋ".trimmingCharacters(in: .whitespaces))
    }

    func testFullPlaceOfBirthSkipsEmptyParts() {
        let doc = EidDocument(fields: [
            .placeOfBirth: "BEOGRAD",
            .communityOfBirth: "",          // empty -> skipped
            .stateOfBirth: "REPUBLIKA SRBIJA",
        ])
        XCTAssertEqual(doc.fullPlaceOfBirth, "BEOGRAD, REPUBLIKA SRBIJA")
    }

    func testDateFormatting() {
        XCTAssertEqual(EidDocument.formatDate("19051989"), "19.05.1989")
        XCTAssertEqual(EidDocument.formatDate(""), "")          // unchanged if malformed
        XCTAssertEqual(EidDocument.formatDate("123"), "123")
    }

    func testUnknownFieldsAreSeparate() {
        var doc = EidDocument()
        doc.fields[.documentRegNumber] = "010231713"
        doc.unknownFields[1545] = "SRB"
        XCTAssertEqual(doc[.documentRegNumber], "010231713")
        XCTAssertEqual(doc.unknownFields[1545], "SRB")
    }

    func testNewlyMappedTagsExist() {
        // Regression: 1548 (serial) and 1581 (address label) must be known fields,
        // matching bas-celik's coverage.
        XCTAssertEqual(EidField(rawValue: 1548), .documentSerialNumber)
        XCTAssertEqual(EidField(rawValue: 1581), .addressLabel)
    }
}
