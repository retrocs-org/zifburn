import Foundation

enum Checksum {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// The classic 16-bit byte sum most EPROM programmers display.
    static func sum16(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        data.withUnsafeBytes { buffer in
            for byte in buffer { sum &+= UInt32(byte) }
        }
        return UInt16(truncatingIfNeeded: sum)
    }

    /// Returns the fill byte if every byte is identical (e.g. a blank 0xFF chip).
    static func uniformByte(_ data: Data) -> UInt8? {
        guard let first = data.first else { return nil }
        return data.allSatisfy { $0 == first } ? first : nil
    }
}

enum IntelHex {
    enum DecodeError: LocalizedError {
        case badRecord(line: Int)
        case badChecksum(line: Int)
        case missingEndRecord
        case imageTooLarge(line: Int, limit: Int)

        var errorDescription: String? {
            switch self {
            case .badRecord(let line): "Malformed Intel HEX record on line \(line)."
            case .badChecksum(let line): "Intel HEX checksum mismatch on line \(line)."
            case .missingEndRecord: "Intel HEX file is missing its end-of-file record."
            case .imageTooLarge(let line, let limit): "Intel HEX address on line \(line) exceeds the \(limit / 1024 / 1024) MiB buffer import limit. Convert the image to a bounded binary first."
            }
        }
    }

    static func encode(_ data: Data, bytesPerRecord: Int = 16) -> String {
        let bytes = [UInt8](data)
        var out = ""
        var upper = -1
        var offset = 0
        while offset < bytes.count {
            let high = offset >> 16
            if high != upper {
                upper = high
                out += record(type: 0x04, address: 0, payload: [UInt8((high >> 8) & 0xFF), UInt8(high & 0xFF)])
            }
            let count = min(bytesPerRecord, bytes.count - offset, 0x10000 - (offset & 0xFFFF))
            out += record(type: 0x00, address: offset & 0xFFFF, payload: Array(bytes[offset..<(offset + count)]))
            offset += count
        }
        out += ":00000001FF\n"
        return out
    }

    /// Bound dense expansion of sparse addresses before allocating memory.
    static let maximumImageBytes = 64 * 1024 * 1024

    static func decode(_ text: String, fill: UInt8 = 0xFF, maximumBytes: Int = maximumImageBytes) throws -> Data {
        var out: [UInt8] = []
        var base = 0
        var lineNumber = 0
        var ended = false

        for raw in text.split(whereSeparator: \.isNewline) {
            lineNumber += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard !ended else { throw DecodeError.badRecord(line: lineNumber) }
            guard line.hasPrefix(":"), let bytes = parseHex(line.dropFirst()), bytes.count >= 5 else {
                throw DecodeError.badRecord(line: lineNumber)
            }
            let count = Int(bytes[0])
            guard bytes.count == count + 5 else { throw DecodeError.badRecord(line: lineNumber) }
            guard bytes.reduce(UInt8(0), &+) == 0 else { throw DecodeError.badChecksum(line: lineNumber) }

            let address = (Int(bytes[1]) << 8) | Int(bytes[2])
            let payload = Array(bytes[4..<(4 + count)])

            switch bytes[3] {
            case 0x00:
                guard address + count <= 0x10000 else { throw DecodeError.badRecord(line: lineNumber) }
                let start = base + address
                let end = start + count
                guard end <= maximumBytes else { throw DecodeError.imageTooLarge(line: lineNumber, limit: maximumBytes) }
                if out.count < end {
                    out.append(contentsOf: repeatElement(fill, count: end - out.count))
                }
                for (i, b) in payload.enumerated() { out[start + i] = b }
            case 0x01 where count == 0 && address == 0:
                ended = true
            case 0x02 where payload.count == 2 && address == 0:
                base = ((Int(payload[0]) << 8) | Int(payload[1])) << 4
            case 0x04 where payload.count == 2 && address == 0:
                base = ((Int(payload[0]) << 8) | Int(payload[1])) << 16
            case 0x03, 0x05:
                guard count == 4 && address == 0 else { throw DecodeError.badRecord(line: lineNumber) }
                break // Valid execution start addresses do not change ROM data.
            default:
                throw DecodeError.badRecord(line: lineNumber)
            }
        }
        guard ended else { throw DecodeError.missingEndRecord }
        return Data(out)
    }

    private static func record(type: UInt8, address: Int, payload: [UInt8]) -> String {
        var bytes: [UInt8] = [UInt8(payload.count), UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF), type]
        bytes += payload
        let sum = bytes.reduce(UInt8(0), &+)
        bytes.append(0 &- sum)
        return ":" + bytes.map { String(format: "%02X", $0) }.joined() + "\n"
    }

    private static func parseHex<S: StringProtocol>(_ s: S) -> [UInt8]? {
        let chars = Array(s.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append((hi << 4) | lo)
            i += 2
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: c - 48
        case 65...70: c - 55
        case 97...102: c - 87
        default: nil
        }
    }
}

/// Majority vote over several reads of the same chip.
struct StabilityAnalysis: Sendable {
    let consensus: Data
    let unstable: IndexSet

    init(_ images: [Data]) {
        let arrays = images.map { [UInt8]($0) }
        let count = arrays.first?.count ?? 0
        var out = [UInt8](repeating: 0, count: count)
        var unstable = IndexSet()
        for i in 0..<count {
            let first = arrays[0][i]
            var identical = true
            for a in arrays.dropFirst() where a[i] != first {
                identical = false
                break
            }
            if identical {
                out[i] = first
                continue
            }
            unstable.insert(i)
            var best = first
            var bestVotes = 0
            for a in arrays {
                let value = a[i]
                let votes = arrays.reduce(0) { $0 + ($1[i] == value ? 1 : 0) }
                if votes > bestVotes {
                    best = value
                    bestVotes = votes
                }
            }
            out[i] = best
        }
        consensus = Data(out)
        self.unstable = unstable
    }
}

/// Byte-aligned comparison of two images, with a note about any extra tail.
struct BufferDiff: Sendable {
    let differences: IndexSet
    let anchors: [Int]
    let tailNote: String?

    init(_ a: Data, _ b: Data) {
        let x = [UInt8](a), y = [UInt8](b)
        let n = min(x.count, y.count)
        var diff = IndexSet()
        var anchors: [Int] = []
        var inRun = false
        for i in 0..<n {
            if x[i] != y[i] {
                diff.insert(i)
                if !inRun, anchors.count < 10_000 { anchors.append(i) }
                inRun = true
            } else {
                inRun = false
            }
        }
        if x.count == y.count {
            tailNote = nil
        } else {
            let longer = x.count > y.count ? x : y
            let tail = longer[n...]
            let which = x.count > y.count ? "the buffer" : "the file"
            let extra = longer.count - n
            if tail.allSatisfy({ $0 == 0xFF }) || tail.allSatisfy({ $0 == 0x00 }) {
                tailNote = "\(which) is \(extra) bytes longer (padding only)"
            } else {
                tailNote = "\(which) has \(extra) extra bytes of real data"
            }
        }
        differences = diff
        self.anchors = anchors
    }
}

enum HexFormatter {
    struct Row {
        var address: String
        var hex: String
        var ascii: String
        var start: Int = 0
        var bytes: [UInt8] = []
    }

    static func byte(_ b: UInt8) -> String {
        String([digits[Int(b >> 4)], digits[Int(b & 0x0F)]])
    }

    static func asciiChar(_ b: UInt8) -> String {
        (0x20...0x7E).contains(b) ? String(Character(UnicodeScalar(b))) : "·"
    }

    private static let digits = Array("0123456789ABCDEF")

    static func row(_ data: Data, row: Int, addressDigits: Int) -> Row {
        let start = row * 16
        let end = min(start + 16, data.count)

        var address = String(start, radix: 16, uppercase: true)
        if address.count < addressDigits {
            address = String(repeating: "0", count: addressDigits - address.count) + address
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        var hex = ""
        hex.reserveCapacity(49)
        var ascii = ""
        ascii.reserveCapacity(16)
        let base = data.startIndex

        for i in 0..<16 {
            if i == 8 { hex.append(" ") }
            if start + i < end {
                let b = data[base + start + i]
                bytes.append(b)
                hex.append(digits[Int(b >> 4)])
                hex.append(digits[Int(b & 0x0F)])
                hex.append(" ")
                ascii.append((0x20...0x7E).contains(b) ? Character(UnicodeScalar(b)) : "·")
            } else {
                hex.append("   ")
            }
        }
        return Row(address: address, hex: hex, ascii: ascii, start: start, bytes: bytes)
    }
}
