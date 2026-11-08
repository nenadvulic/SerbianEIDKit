# SerbianEIDKit

[![CI](https://github.com/nenadvulic/SerbianEIDKit/actions/workflows/ci.yml/badge.svg)](https://github.com/nenadvulic/SerbianEIDKit/actions/workflows/ci.yml)

A small, dependency-free Swift package that reads the **Serbian electronic identity
card (lična karta / лична карта)** from a contact smart-card reader on **iOS/iPadOS 16+**
and **macOS 13+**, using Apple's [CryptoTokenKit](https://developer.apple.com/documentation/cryptotokenkit)
(`TKSmartCard`).

The card is read **in the clear**: no PIN, no secure messaging (BAC/PACE). The protocol
was reconstructed from the official reader application and validated against real cards.

> ⚖️ For interoperability and research on **your own** card. eID data is personal data,
> handle it accordingly.

## Features

- Reads the **document**, **personal** and **residence** files, plus the **cardholder photo** (JPEG).
- Pure Swift, no third-party dependencies.
- Async/await API, with an optional APDU-level logging hook.
- Keeps unmapped TLV tags in `unknownFields` so nothing read from the card is lost.

## Installation

Swift Package Manager: add the dependency in Xcode
(*File ▸ Add Package Dependencies…*) with this repository's URL, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nenadvulic/SerbianEIDKit.git", from: "1.0.0"),
],
```

Then add the **Smart Card** capability to your app target (entitlement
`com.apple.security.smartcard`).

## Usage

```swift
import SerbianEIDKit

let reader = try await SerbianEIDReader()     // opens the first slot holding a card

// Optional: observe the APDU exchange
reader.onLog = { print($0) }

let document = try await reader.readAll()
print(document.fullName)                       // "АЛЕКСАНДАР MIODRAG КРСТИЋ"
print(document[.personalNumber])               // JMBG
print(document.dateOfBirthFormatted,
      "·", document.fullPlaceOfBirth)

let jpeg = try await reader.readPhoto()        // UIImage(data:) / NSImage(data:)
```

`readAll()` returns an ``EidDocument``; known fields are in `fields` (keyed by `EidField`),
and any extra tags are in `unknownFields`. `document.variant` tells you which card was read
(`.citizen` / `.foreigner` / `.residence`), and a non-ID card throws `EidError.unsupportedCard`.

### Latin transliteration

The card stores most personal fields in Cyrillic. Get a Latin copy (Gaj's Latin):

```swift
let latin = document.latinized()               // "КРСТИЋ" → "KRSTIĆ"
SerbianTransliteration.toLatin("ЊЕГОШ")        // "NJEGOŠ"
```

### JSON serialization

`EidDocument` is `Codable`, useful to send the document to a backend (KYC/onboarding),
cache it, or snapshot it in tests. Keys are human-readable (`surname`, `givenName`, …):

```swift
let json = try JSONEncoder().encode(document)
let back = try JSONDecoder().decode(EidDocument.self, from: json)
```

## How the card is read

The card is an ISO&nbsp;7816-4 contact chip. Reading is a fixed sequence of APDUs:

### 1. Select the applet (SELECT AID)

```
00 A4 04 0C 0B  F3 81 00 00 02 53 45 52 49 44 01
```

The AID ends in an ASCII tag identifying the card variant: `SERID` (citizen),
`SERIF` (foreigner) or `SERRP` (residence permit). The reader tries all three.

### 2. Read each elementary file

The data lives in four elementary files (EF), selected by file identifier (FID):

| FID    | Contents |
|--------|----------|
| `0F02` | Document (number, type, dates, issuing authority) |
| `0F03` | Personal (name, JMBG, birth, sex) |
| `0F04` | Residence (address) |
| `0F06` | Photo (JPEG) |

For each file:

```
SELECT FILE   00 A4 08 00 02 <FID>        ← note: NO Le byte (real cards reject it with 6F00)
READ BINARY   00 B0 <offHi> <offLo> <len> ← looped in blocks of ≤ 255 bytes
```

Each file begins with a **4-byte wrapper header** whose bytes `[2..3]` hold the payload
length in **little-endian**. We read those 4 bytes first, then read exactly that many
bytes of payload. (On iOS, `TKSmartCard` returns SELECT FILE **without** the FCI, so the
length must come from this header rather than from the SELECT response.) The photo file
has an additional 4-byte inner header before the JPEG.

### 3. Parse the proprietary TLV

Each payload is a sequence of little-endian TLV records, terminated by a `0` tag
(the rest is padding):

```
tag    : UInt16 (little-endian)
length : UInt16 (little-endian)
value  : <length> bytes   (UTF-8, falling back to ISO-8859-1)
```

### Tag reference

The numeric tags are the ones actually written on the chip (extracted from the official
app's tag mappers and validated on card). The main fields:

| Tag  | Field | File |
|------|-------|------|
| 1546 | document registration number | DOCUMENT |
| 1547 | document type | DOCUMENT |
| 1548 | document serial number | DOCUMENT |
| 1549 | issuing date | DOCUMENT |
| 1550 | expiry date | DOCUMENT |
| 1551 | issuing authority | DOCUMENT |
| 1558 | personal number (JMBG) | PERSONAL |
| 1559 | surname | PERSONAL |
| 1560 | given name | PERSONAL |
| 1561 | parent given name | PERSONAL |
| 1562 | sex | PERSONAL |
| 1563 | place of birth | PERSONAL |
| 1564 | community of birth | PERSONAL |
| 1565 | state of birth | PERSONAL |
| 1566 | date of birth | PERSONAL |
| 1567 | state-of-birth code | PERSONAL |
| 1568–1581 | residence (state, community, place, street, number, …) | RESIDENCE |

Dates are `DDMMYYYY`; `EidDocument.formatDate` renders them as `DD.MM.YYYY`.

## Hardware notes

- Requires a **CCID** contact reader. On an iPhone 15+/iPad with USB-C, a USB-C reader
  (or a USB reader via a USB-C adapter) connects directly.
- Some readers draw more power than a phone supplies, a **powered USB-C hub** helps.
- Does **not** work on the iOS Simulator (`TKSmartCardSlotManager.default` is `nil`).

## Example app

[`Examples/EidReaderDemo`](Examples/EidReaderDemo) is a minimal SwiftUI app that uses the
package: tap **Read card** to display the fields, the photo and the APDU log.

## Credits

The field mapping and read protocol are consistent with
[bas-celik](https://github.com/ubavic/bas-celik), the reference desktop reader for Serbian
documents. This package focuses on reading the identity card's data files on Apple platforms.

## License

MIT. See [LICENSE](LICENSE).
