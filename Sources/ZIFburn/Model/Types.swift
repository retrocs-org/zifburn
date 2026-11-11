import SwiftUI

struct DeviceInfo: Equatable {
    struct Field: Equatable {
        var key: String
        var value: String
    }

    var name: String
    var fields: [Field]
    var memoryBytes: Int?
    var package: String?
}

struct ChipBuffer: Identifiable {
    enum Origin {
        case chip(device: String, date: Date)
        case file(URL)
    }

    let id = UUID()
    var data: Data
    var origin: Origin
    /// Extra files minipro produced during a read (e.g. EEPROM or fuse pages).
    var extraFiles: [URL] = []
    /// Changed in ZIFburn (trimmed/padded) since it was read or opened.
    var modified = false

    var title: String {
        switch origin {
        case .chip(let device, _): DeviceName.display(device)
        case .file(let url): url.lastPathComponent
        }
    }

    var subtitle: String {
        switch origin {
        case .chip(_, let date):
            "Read from chip at \(date.formatted(date: .omitted, time: .standard))"
        case .file(let url):
            url.deletingLastPathComponent().path
        }
    }

    var suggestedBaseName: String {
        switch origin {
        case .chip(let device, _): Sanitize.fileName(device)
        case .file(let url): url.deletingPathExtension().lastPathComponent
        }
    }
}

/// Bytes highlighted in the hex view, with jump targets for ↑/↓ navigation.
struct ByteMarks: Equatable {
    enum Kind { case find, diff, unstable }

    var kind: Kind
    var title: String
    var indexes: IndexSet
    /// Start offset of each match / differing run (capped).
    var anchors: [Int]
}

struct BufferStats: Equatable, Sendable {
    var crc32: UInt32
    var sum16: UInt16
    var uniformByte: UInt8?

    init(_ data: Data) {
        crc32 = Checksum.crc32(data)
        sum16 = Checksum.sum16(data)
        uniformByte = Checksum.uniformByte(data)
    }
}

struct LogEntry: Identifiable {
    enum Kind {
        case command, stdout, stderr, info, success, error

        func color(in theme: Theme) -> Color {
            switch self {
            case .command: theme.accent
            case .stdout: theme.text
            case .stderr, .info: theme.secondaryText
            case .success: theme.success
            case .error: theme.error
            }
        }
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let text: String
}

struct Activity: Equatable {
    var title: String
    var detail = ""
    /// Overall progress across all stages (erase → write → verify).
    var progress: Double?
    /// Expected number of stages; grows by one if minipro starts with an erase.
    var stages = 1
    var stageIndex = 0
    var stageLabel: String?
    var countedErase = false
}

/// A hint for a failed operation, optionally with a one-click fix + retry.
struct FixSuggestion: Equatable {
    enum Action: Equatable {
        case ignoreIDError, ignoreSizeError, padToChip
    }

    var hint: String
    var action: Action?
    var actionLabel: String?
}

/// The last user operation, so a suggested fix can run it again.
enum RetryableOperation: Equatable {
    case read, writeBuffer, writeFile(URL), verifyBuffer, verifyFile(URL)
    case blankCheck, erase, readID, burnBuffer, burnFile(URL)

    var usesBuffer: Bool {
        switch self {
        case .writeBuffer, .verifyBuffer, .burnBuffer: true
        default: false
        }
    }
}

struct Outcome: Equatable {
    var success: Bool
    var message: String
    var date = Date()
}

enum PendingConfirmation: Identifiable {
    case writeBuffer
    case writeFile(URL)
    case burnBuffer
    case burnFile(URL)
    case erase
    case firmware(URL)
    case selfTest
    /// Duplicate: ask for the master chip, then read it.
    case duplicateMaster
    /// Batch / duplicate: ask for the next blank chip and write the buffer.
    case batchNext(done: Int, failed: Int, lastFailed: Bool)
    /// Burn set: next image in the set goes onto a fresh chip.
    case burnSetNext(files: [URL], index: Int, lastFailed: Bool)
    /// Adapter job: set the bank switches, then process this bank.
    case adapterBank(job: AdapterJob, bank: Int, lastFailed: Bool)

    var id: String {
        switch self {
        case .burnBuffer: "burnBuffer"
        case .burnFile(let url): "burnFile:\(url.path)"
        case .writeBuffer: "writeBuffer"
        case .writeFile(let url): "writeFile:\(url.path)"
        case .erase: "erase"
        case .firmware(let url): "firmware:\(url.path)"
        case .selfTest: "selfTest"
        case .duplicateMaster: "duplicateMaster"
        case .batchNext(let done, let failed, let lastFailed): "batch:\(done):\(failed):\(lastFailed)"
        case .burnSetNext(let files, let index, let lastFailed):
            "burnset:\(index):\(lastFailed):\(files.map(\.lastPathComponent).joined(separator: "|"))"
        case .adapterBank(let job, let bank, let lastFailed):
            "adapter:\(job.kind.rawValue):\(job.targetID):\(bank):\(lastFailed)"
        }
    }
}

enum BufferExportFormat {
    case binary, intelHex
}

enum Sanitize {
    static func fileName(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(mapped)
    }
}
