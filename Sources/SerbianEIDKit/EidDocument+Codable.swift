//
//  EidDocument+Codable.swift
//  SerbianEIDKit
//
//  JSON serialization with human-readable keys, e.g.:
//
//    {
//      "variant": "citizen",
//      "fields": { "surname": "КРСТИЋ", "givenName": "АЛЕКСАНДАР", ... },
//      "unknownFields": { "1545": "SRB" }
//    }
//
//  Useful on iOS to send the document to a backend (KYC/onboarding), cache it, or test.
//

import Foundation

extension EidDocument: Codable {

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private enum TopKey: String, CodingKey {
        case fields, unknownFields, variant
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TopKey.self)

        var fieldsContainer = container.nestedContainer(keyedBy: DynamicKey.self, forKey: .fields)
        for (field, value) in fields {
            try fieldsContainer.encode(value, forKey: DynamicKey(field.key))
        }

        if !unknownFields.isEmpty {
            var unknownContainer = container.nestedContainer(keyedBy: DynamicKey.self, forKey: .unknownFields)
            for (tag, value) in unknownFields {
                try unknownContainer.encode(value, forKey: DynamicKey(String(tag)))
            }
        }

        try container.encodeIfPresent(variant, forKey: .variant)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopKey.self)

        var fields: [EidField: String] = [:]
        if let fieldsContainer = try? container.nestedContainer(keyedBy: DynamicKey.self, forKey: .fields) {
            for codingKey in fieldsContainer.allKeys {
                guard let field = EidField(key: codingKey.stringValue) else { continue }
                fields[field] = try fieldsContainer.decode(String.self, forKey: codingKey)
            }
        }

        var unknownFields: [Int: String] = [:]
        if let unknownContainer = try? container.nestedContainer(keyedBy: DynamicKey.self, forKey: .unknownFields) {
            for codingKey in unknownContainer.allKeys {
                guard let tag = Int(codingKey.stringValue) else { continue }
                unknownFields[tag] = try unknownContainer.decode(String.self, forKey: codingKey)
            }
        }

        let variant = try container.decodeIfPresent(EidCardVariant.self, forKey: .variant)

        self.init(fields: fields, unknownFields: unknownFields, variant: variant)
    }
}
