//
//  SerbianEIDReader.swift
//  SerbianEIDKit
//
//  Reads the Serbian electronic identity card (eID) over a PC/SC-style contact
//  reader using CryptoTokenKit (`TKSmartCard`). The data is read in the clear:
//  no PIN, no BAC/PACE.
//
//  The protocol (AIDs, file identifiers, APDUs, TLV layout) was reconstructed from
//  the official reader app and validated against real cards. See README.md.
//

import Foundation
import CryptoTokenKit

// MARK: - Protocol constants

/// Low-level protocol constants reconstructed from the official app.
enum EidProtocol {
    // Application identifiers: citizen / foreigner / residence-permit variants.
    static let aidCitizen:   [UInt8] = [0xF3,0x81,0x00,0x00,0x02,0x53,0x45,0x52,0x49,0x44,0x01] // SERID
    static let aidForeigner: [UInt8] = [0xF3,0x81,0x00,0x00,0x02,0x53,0x45,0x52,0x49,0x46,0x01] // SERIF
    static let aidResidence: [UInt8] = [0xF3,0x81,0x00,0x00,0x02,0x53,0x45,0x52,0x52,0x50,0x01] // SERRP
    static let allAIDs: [[UInt8]] = [aidCitizen, aidForeigner, aidResidence]

    // Elementary-file identifiers.
    static let documentFile:  [UInt8] = [0x0F, 0x02]
    static let personalFile:  [UInt8] = [0x0F, 0x03]
    static let residenceFile: [UInt8] = [0x0F, 0x04]
    static let photoFile:     [UInt8] = [0x0F, 0x06]

    /// The only ATR that uses reading "strategy A". Everything else uses "strategy B".
    static let apolloATR: [UInt8] = [
        0x3B,0xB9,0x18,0x00,0x81,0x31,0xFE,0x9E,0x80,0x73,0xFF,0x61,0x40,0x83,0x00,0x00,0x00,0xDF
    ]
}

// MARK: - Reader

/// Reads a Serbian eID card from a connected contact reader.
///
/// Usage:
/// ```swift
/// let reader = try await SerbianEIDReader()
/// let document = try await reader.readAll()
/// let photo = try await reader.readPhoto()   // JPEG bytes
/// ```
public final class SerbianEIDReader {

    private let card: TKSmartCard
    private let isApollo: Bool

    /// Optional hook receiving human-readable log lines (APDU exchanges, steps).
    public var onLog: ((String) -> Void)?

    private func log(_ message: String) {
        onLog?(message)
    }

    /// Opens the first reader slot that currently holds a card.
    ///
    /// - Parameter slotName: optionally target a specific slot by name; otherwise the
    ///   first slot with a valid card is used.
    /// - Throws: ``EidError/noReader`` if no reader or card is available.
    public init(slotName: String? = nil) async throws {
        guard let manager = TKSmartCardSlotManager.default else { throw EidError.noReader }
        let names = manager.slotNames
        guard !names.isEmpty else { throw EidError.noReader }

        var chosen: TKSmartCard?
        var atrBytes: [UInt8] = []
        for name in (slotName.map { [$0] } ?? names) {
            guard let slot = await manager.getSlot(withName: name),
                  slot.state == .validCard,
                  let smartCard = slot.makeSmartCard() else { continue }
            if let atr = slot.atr?.bytes { atrBytes = [UInt8](atr) }
            chosen = smartCard
            break
        }
        guard let smartCard = chosen else { throw EidError.noReader }

        self.card = smartCard
        self.isApollo = (atrBytes == EidProtocol.apolloATR)
        log("Reader opened. ATR=\(TLVParser.hexString(atrBytes)) → "
            + (isApollo ? "Apollo (strategy A)" : "non-Apollo (strategy B, fallback A)"))
    }

    // MARK: High-level reads

    /// Selects the eID applet and reads the document, personal and residence files.
    public func readAll() async throws -> EidDocument {
        try await withSession {
            let variant = try await self.selectAID()
            var document = EidDocument(variant: variant)
            try await self.readFile(EidProtocol.documentFile, into: &document)
            try await self.readFile(EidProtocol.personalFile, into: &document)
            try await self.readFile(EidProtocol.residenceFile, into: &document)
            return document
        }
    }

    /// Reads the cardholder photo as JPEG bytes (directly decodable by `UIImage`/`NSImage`).
    public func readPhoto() async throws -> Data {
        try await withSession {
            try await self.selectAID()
            return try await self.readElementaryFile(EidProtocol.photoFile, stripTag: true)
        }
    }

    // MARK: Session

    private func withSession<T>(_ body: @escaping () async throws -> T) async throws -> T {
        try await card.beginSession()
        defer { card.endSession() }
        return try await body()
    }

    // MARK: SELECT AID

    /// Selects the eID applet, trying the three AID variants in turn.
    /// - Returns: the matched ``EidCardVariant``.
    /// - Throws: ``EidError/unsupportedCard`` if none of the variants is accepted.
    @discardableResult
    private func selectAID() async throws -> EidCardVariant {
        let variants: [EidCardVariant] = [.citizen, .foreigner, .residence]
        for (index, aid) in EidProtocol.allAIDs.enumerated() {
            // 00 A4 04 0C <Lc=0B> <AID(11)>
            let apdu = [0x00, 0xA4, 0x04, 0x0C, UInt8(aid.count)] + aid
            let (_, sw1, sw2) = try await transmit(apdu)
            if sw1 == 0x90 && sw2 == 0x00 {
                log("✓ applet selected: \(variants[index])")
                return variants[index]
            }
        }
        throw EidError.unsupportedCard
    }

    // MARK: File read + TLV parsing

    private func readFile(_ fid: [UInt8], into document: inout EidDocument) async throws {
        log("── Reading EF \(TLVParser.hexString(fid)) ──")
        let raw = try await readElementaryFile(fid, stripTag: false)
        let records = TLVParser.parse(raw)
        log("EF \(TLVParser.hexString(fid)): \(raw.count) bytes, \(records.count) tags")
        for record in records {
            if let field = EidField(rawValue: record.tag) {
                document.fields[field] = record.value
                log("   tag \(record.tag) = \(record.value)")
            } else {
                document.unknownFields[record.tag] = record.value
                log("   tag \(record.tag) (unknown) = \(record.value)")
            }
        }
    }

    /// Reads an elementary file, choosing the strategy based on the ATR.
    ///
    /// Apollo chips use strategy A. All other chips use strategy B, with an automatic
    /// fallback to A if B fails (unknown ATR / atypical card).
    private func readElementaryFile(_ fid: [UInt8], stripTag: Bool) async throws -> Data {
        if isApollo { return try await readApolloStyle(fid, stripTag: stripTag) }
        do {
            return try await readGemaltoStyle(fid, stripTag: stripTag)
        } catch {
            // Re-select the applet (the failure may have disturbed the state), then try A.
            try? await selectAID()
            return try await readApolloStyle(fid, stripTag: stripTag)
        }
    }

    /// Strategy A (Apollo): a 6-byte header carries the little-endian length at [4..5].
    private func readApolloStyle(_ fid: [UInt8], stripTag: Bool) async throws -> Data {
        try await selectFile(fid)
        let header = try await readBinary(offset: 0, length: 6)
        if header.allSatisfy({ $0 == 0xFF }) { return Data() }
        var length = (Int(header[5]) << 8) + Int(header[4])
        var offset = 6
        if stripTag { length -= 4; offset = 10 }
        var out = Data()
        while length > 0 {
            let data = try await readBinary(offset: offset, length: length)
            out.append(data)
            offset += data.count
            length -= data.count
        }
        return out
    }

    /// Strategy B (Gemalto / SmartCafeExpert7 and newer).
    ///
    /// On iOS, `TKSmartCard` returns the SELECT FILE response **without the FCI**
    /// (case 3, no Le), so we cannot bootstrap the length from it. Instead we read the
    /// 4-byte wrapper header directly: its bytes `[2..3]` (little-endian) hold the real
    /// content length, and the actual data follows the header. This matches the layout
    /// the official app parses, without depending on the FCI being returned.
    private func readGemaltoStyle(_ fid: [UInt8], stripTag: Bool) async throws -> Data {
        try await selectFile(fid)   // FCI is ignored (empty on iOS)

        let header = try await readBinary(offset: 0, length: 4)
        guard header.count >= 4 else {
            throw EidError.apduFailed(statusWord: "hdr<4", context: "readGemalto header")
        }
        if header.allSatisfy({ $0 == 0xFF }) { return Data() }

        let contentLength = (Int(header[3]) << 8) | Int(header[2])   // little-endian
        guard contentLength > 0 else { return Data() }

        // Read exactly the content that follows the 4-byte header (avoids 0x6700 over-reads).
        let content = try await readBinary(offset: 4, length: contentLength)

        if stripTag {
            // Photo file: a further 4-byte inner header precedes the JPEG bytes.
            return content.count > 4 ? content.subdata(in: 4..<content.count) : Data()
        }
        return content
    }

    // MARK: APDU primitives

    /// SELECT FILE: `00 A4 08 00 <Lc> <FID>` (case 3, **no** Le bytes).
    ///
    /// The original app appended 4 Le bytes, which real cards reject with SW 6F00.
    /// The FCI is still returned without Le.
    @discardableResult
    private func selectFile(_ fid: [UInt8]) async throws -> Data {
        let apdu = [0x00, 0xA4, 0x08, 0x00, UInt8(fid.count)] + fid
        let (data, sw1, sw2) = try await transmit(apdu)
        guard sw1 == 0x90 && sw2 == 0x00 else {
            throw EidError.apduFailed(statusWord: TLVParser.hexString([sw1, sw2]),
                                      context: "selectFile \(TLVParser.hexString(fid))")
        }
        return data
    }

    /// READ BINARY in a loop (blocks of up to 255 bytes): `00 B0 <offHi> <offLo> <len>`.
    private func readBinary(offset: Int, length: Int) async throws -> Data {
        var out = Data()
        var off = offset
        var remaining = length
        while remaining > 0 {
            let chunk = min(remaining, 255)
            let apdu: [UInt8] = [0x00, 0xB0, UInt8((off >> 8) & 0xFF), UInt8(off & 0xFF), UInt8(chunk)]
            let (data, sw1, sw2) = try await transmit(apdu)
            guard sw1 == 0x90 && sw2 == 0x00 else {
                throw EidError.apduFailed(statusWord: TLVParser.hexString([sw1, sw2]),
                                          context: "readBinary@\(off)")
            }
            guard !data.isEmpty else { break }
            out.append(data)
            off += data.count
            remaining -= data.count
        }
        return out
    }

    /// Transmits a raw APDU and returns `(responseBody, SW1, SW2)`.
    private func transmit(_ apdu: [UInt8]) async throws -> (Data, UInt8, UInt8) {
        log("→ APDU  \(TLVParser.hexString(apdu))")
        let response: Data
        do {
            response = try await card.transmit(Data(apdu))
        } catch {
            log("‼︎ transport: \(error)")
            throw EidError.transport("\(error)")
        }
        guard response.count >= 2 else {
            log("‼︎ response < 2 bytes")
            throw EidError.transport("response shorter than 2 bytes")
        }
        let sw1 = response[response.count - 2]
        let sw2 = response[response.count - 1]
        let body = response.subdata(in: 0..<(response.count - 2))
        let preview = body.isEmpty ? "" : "  " + TLVParser.hexString(Array(body.prefix(32)))
            + (body.count > 32 ? "…" : "")
        log("← \(String(format: "%02X%02X", sw1, sw2)) (\(body.count) bytes)\(preview)")
        return (body, sw1, sw2)
    }
}
