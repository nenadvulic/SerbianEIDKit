//
//  EidModels.swift
//  SerbianEIDKit
//
//  Data model for the Serbian electronic identity card (eID).
//

import Foundation

/// A field stored on the card, identified by its real TLV tag (`UInt16`, little-endian)
/// as written on the chip.
///
/// These numeric values are **not** arbitrary: they were extracted from the official
/// reader app's tag mappers (`DOCUMENT_/PERSONAL_/RESIDENCE_TAGMAPPER`) and validated
/// against a real card. They are the tags that actually appear in the TLV stream.
public enum EidField: Int, CaseIterable, Sendable {
    // DOCUMENT file (EF 0F02)
    case documentRegNumber    = 1546
    case documentType         = 1547
    case documentSerialNumber = 1548
    case issuingDate          = 1549
    case expiryDate           = 1550
    case issuingAuthority     = 1551
    case chipSerialNumber     = 1681
    case documentName         = 1682

    // PERSONAL file (EF 0F03)
    case personalNumber    = 1558   // JMBG
    case surname           = 1559
    case givenName         = 1560
    case parentGivenName   = 1561
    case sex               = 1562
    case placeOfBirth      = 1563
    case communityOfBirth  = 1564
    case stateOfBirth      = 1565
    case dateOfBirth       = 1566
    case stateOfBirthCode  = 1567
    case nationalityFull   = 1583
    case purposeOfStay     = 1683
    case enote             = 1684

    // RESIDENCE file (EF 0F04)
    case state             = 1568
    case community         = 1569
    case place             = 1570
    case street            = 1571
    case houseNumber       = 1572
    case houseLetter       = 1573
    case entrance          = 1574
    case floor             = 1575
    case apartmentNumber   = 1578
    case addressDate       = 1580
    case addressLabel      = 1581
}

/// The decoded contents of an eID card.
public struct EidDocument: Equatable, Sendable {
    /// Known field values, keyed by their ``EidField``.
    public var fields: [EidField: String]

    /// Any TLV records whose tag is not a known ``EidField``, keyed by the raw tag.
    /// Kept so no data read from the card is silently discarded.
    public var unknownFields: [Int: String]

    public init(fields: [EidField: String] = [:], unknownFields: [Int: String] = [:]) {
        self.fields = fields
        self.unknownFields = unknownFields
    }

    /// Returns the value for a field, or an empty string if absent.
    public subscript(_ field: EidField) -> String { fields[field] ?? "" }

    /// Full name as composed by the official app: `given parent surname`.
    public var fullName: String {
        "\(self[.givenName]) \(self[.parentGivenName]) \(self[.surname])"
            .trimmingCharacters(in: .whitespaces)
    }

    /// Place of birth as composed by the official app: `place, community, state`.
    public var fullPlaceOfBirth: String {
        [self[.placeOfBirth], self[.communityOfBirth], self[.stateOfBirth]]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Date of birth formatted as `DD.MM.YYYY`.
    public var dateOfBirthFormatted: String { EidDocument.formatDate(self[.dateOfBirth]) }

    /// Converts a `DDMMYYYY` date string into `DD.MM.YYYY`.
    /// Non-conforming input is returned unchanged.
    public static func formatDate(_ value: String) -> String {
        guard value.count == 8 else { return value }
        let day = value.prefix(2)
        let month = value.dropFirst(2).prefix(2)
        let year = value.suffix(4)
        return "\(day).\(month).\(year)"
    }
}

/// Errors thrown while reading an eID card.
public enum EidError: Error, CustomStringConvertible, Sendable {
    /// No card reader / slot with a present card was found.
    case noReader
    /// The card did not answer as a Serbian eID (unexpected ATR).
    case cardNotRecognized(atr: String)
    /// An APDU command returned a non-success status word.
    case apduFailed(statusWord: String, context: String)
    /// A low-level transport error occurred.
    case transport(String)

    public var description: String {
        switch self {
        case .noReader:
            return "No card reader or slot is available."
        case .cardNotRecognized(let atr):
            return "Card not recognized as a Serbian eID. ATR=\(atr)"
        case .apduFailed(let sw, let context):
            return "APDU failed [\(context)] SW=\(sw)"
        case .transport(let message):
            return "Transport error: \(message)"
        }
    }
}
