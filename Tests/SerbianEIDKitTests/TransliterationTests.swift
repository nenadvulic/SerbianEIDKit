import XCTest
@testable import SerbianEIDKit

final class TransliterationTests: XCTestCase {

    func testBasicNames() {
        XCTAssertEqual(SerbianTransliteration.toLatin("КРСТИЋ"), "KRSTIĆ")
        XCTAssertEqual(SerbianTransliteration.toLatin("АЛЕКСАНДАР"), "ALEKSANDAR")
        XCTAssertEqual(SerbianTransliteration.toLatin("Ђорђе"), "Đorđe")
    }

    func testAlreadyLatinIsUnchanged() {
        XCTAssertEqual(SerbianTransliteration.toLatin("BEOGRAD"), "BEOGRAD")
        XCTAssertEqual(SerbianTransliteration.toLatin("SAVSKI VENAC"), "SAVSKI VENAC")
    }

    func testDigraphsRespectCase() {
        XCTAssertEqual(SerbianTransliteration.toLatin("њ"), "nj")
        XCTAssertEqual(SerbianTransliteration.toLatin("Његош"), "Njegoš")   // title case
        XCTAssertEqual(SerbianTransliteration.toLatin("ЊЕГОШ"), "NJEGOŠ")   // all caps
        XCTAssertEqual(SerbianTransliteration.toLatin("ЏЕМ"), "DŽEM")
    }

    func testDocumentLatinized() {
        let doc = EidDocument(fields: [.surname: "КРСТИЋ", .place: "BEOGRAD"],
                              unknownFields: [1545: "СРБ"],
                              variant: .citizen)
        let latin = doc.latinized()
        XCTAssertEqual(latin[.surname], "KRSTIĆ")
        XCTAssertEqual(latin[.place], "BEOGRAD")          // untouched
        XCTAssertEqual(latin.unknownFields[1545], "SRB")
        XCTAssertEqual(latin.variant, .citizen)           // metadata preserved
    }
}
