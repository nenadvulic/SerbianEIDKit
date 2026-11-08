//
//  SerbianTransliteration.swift
//  SerbianEIDKit
//
//  Serbian Cyrillic → Latin (Gaj's Latin) transliteration. The card stores most
//  personal fields in Cyrillic (e.g. "КРСТИЋ"); many apps display/submit Latin.
//  Fields already in Latin (e.g. place names) pass through unchanged.
//

import Foundation

public enum SerbianTransliteration {

    private static let map: [Character: String] = [
        "А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Ђ": "Đ", "Е": "E",
        "Ж": "Ž", "З": "Z", "И": "I", "Ј": "J", "К": "K", "Л": "L", "Љ": "Lj",
        "М": "M", "Н": "N", "Њ": "Nj", "О": "O", "П": "P", "Р": "R", "С": "S",
        "Т": "T", "Ћ": "Ć", "У": "U", "Ф": "F", "Х": "H", "Ц": "C", "Ч": "Č",
        "Џ": "Dž", "Ш": "Š",
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ђ": "đ", "е": "e",
        "ж": "ž", "з": "z", "и": "i", "ј": "j", "к": "k", "л": "l", "љ": "lj",
        "м": "m", "н": "n", "њ": "nj", "о": "o", "п": "p", "р": "r", "с": "s",
        "т": "t", "ћ": "ć", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "č",
        "џ": "dž", "ш": "š",
    ]

    /// Transliterates a Serbian Cyrillic string to Latin. Non-Cyrillic characters
    /// are kept as-is. Uppercase digraphs are expanded correctly in all-caps context
    /// (e.g. "ЉУБА" → "LJUBA", but "Љуба" → "Ljuba").
    public static func toLatin(_ string: String) -> String {
        let characters = Array(string)
        var result = ""
        for (index, character) in characters.enumerated() {
            guard let mapped = map[character] else {
                result.append(character)
                continue
            }
            if mapped.count == 2, character.isUppercase {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let allCaps = next == nil || next!.isUppercase || !next!.isLetter
                result += allCaps ? mapped.uppercased() : mapped
            } else {
                result += mapped
            }
        }
        return result
    }
}

public extension EidDocument {
    /// A copy of the document with every field value transliterated to Latin.
    func latinized() -> EidDocument {
        EidDocument(
            fields: fields.mapValues(SerbianTransliteration.toLatin),
            unknownFields: unknownFields.mapValues(SerbianTransliteration.toLatin),
            variant: variant
        )
    }
}
