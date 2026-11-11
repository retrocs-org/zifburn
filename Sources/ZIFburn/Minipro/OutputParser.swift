import Foundation

enum MiniproLocator {
    /// Apps launched from Finder get a minimal PATH, so check the usual
    /// Homebrew / MacPorts locations explicitly before falling back to PATH.
    static let candidates = [
        "/opt/homebrew/bin/minipro",
        "/usr/local/bin/minipro",
        "/opt/local/bin/minipro",
        "/usr/bin/minipro",
    ]

    static func locate(override: String?) -> URL? {
        let fm = FileManager.default
        if let override = override?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let path = "\(dir)/minipro"
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}

enum ProgrammerStatus: Equatable {
    case unknown
    case disconnected(String)
    case connected(model: String, firmware: String?, qFlag: String?)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .unknown: "Checking…"
        case .disconnected: "No programmer"
        case .connected(let model, _, _): model
        }
    }

    var subtitle: String? {
        if case .connected(_, let fw, _) = self, let fw { return "fw \(fw)" }
        return nil
    }

    var help: String {
        switch self {
        case .unknown: "Looking for a programmer…"
        case .disconnected(let reason): "\(reason)\nClick to check again."
        case .connected(let model, let fw, _): "\(model)\(fw.map { " – firmware \($0)" } ?? "")\nClick to check again."
        }
    }

    /// Value for minipro's `-q` option, used to filter the device list.
    var qFlag: String? {
        if case .connected(_, _, let q) = self { return q }
        return nil
    }
}

enum OutputParser {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")
    private static let percent = try! NSRegularExpression(pattern: "(\\d{1,3})\\s*%")
    private static let firmware = try! NSRegularExpression(pattern: "(\\d{1,2}\\.\\d{1,2}\\.\\d{1,3})")
    private static let sizeTerm = try! NSRegularExpression(pattern: "(0x[0-9A-Fa-f]+|\\d+)\\s*(bytes?|words?)?", options: .caseInsensitive)

    /// Strips ANSI escapes (minipro uses `ESC[K` to clear the line) and whitespace.
    static func clean(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return ansi.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts a 0…1 progress value from e.g. "Writing Code...  42%".
    static func progress(in s: String) -> Double? {
        guard let value = lastCapture(percent, in: s), let v = Double(value) else { return nil }
        return min(max(v / 100, 0), 1)
    }

    /// "Writing Code...  42%" → "Writing Code"; nil when there's no stage label.
    static func stageLabel(in s: String) -> String? {
        guard let range = s.range(of: "...") else { return nil }
        let label = s[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }

    static func version(from lines: [String]) -> String? {
        for line in lines {
            if let r = line.range(of: "minipro version ") {
                return line[r.upperBound...].split(separator: " ").first.map(String.init)
            }
        }
        return nil
    }

    static func programmer(from lines: [String], status: Int32) -> ProgrammerStatus {
        let text = lines.joined(separator: "\n")
        let lower = text.lowercased()
        if status != 0 || lower.contains("no programmer") || lower.contains("not found") {
            return .disconnected(lines.last ?? "No programmer found")
        }
        let fw = lastCapture(firmware, in: text)
        // Order matters: most specific tokens first.
        let known: [(token: String, display: String, q: String)] = [
            ("t76", "T76", "t76"),
            ("t56", "T56", "t56"),
            ("t48", "T48", "t48"),
            ("tl866ii", "TL866II+", "tl866ii"),
            ("tl866cs", "TL866CS", "tl866a"),
            ("tl866a", "TL866A", "tl866a"),
        ]
        for entry in known where lower.contains(entry.token) {
            return .connected(model: entry.display, firmware: fw, qFlag: entry.q)
        }
        return .connected(model: lines.first ?? "Programmer", firmware: fw, qFlag: nil)
    }

    /// Filters `minipro -l` output down to device names, dropping banners and errors.
    static func deviceList(from lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            guard !line.isEmpty,
                  !lower.contains("programmer"),
                  !lower.contains("database"),
                  !lower.hasPrefix("no device"),
                  !lower.hasPrefix("abort"),
                  line.range(of: "^\\d+\\)", options: .regularExpression) == nil, // "1) TL866A/CS" menu items
                  !lower.hasPrefix("error"),
                  !lower.hasPrefix("warning"),
                  !lower.hasPrefix("minipro"),
                  !lower.hasPrefix("usage"),
                  !line.hasSuffix(":"),
                  seen.insert(line).inserted
            else { return nil }
            return line
        }
    }

    /// Parses the `Key: Value` block printed by `minipro -d <device>`.
    /// Anything before the `Name:` line (programmer banner etc.) is ignored.
    static func deviceInfo(from lines: [String], fallbackName: String) -> DeviceInfo? {
        var fields: [DeviceInfo.Field] = []
        var started = false
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("Name") == .orderedSame { started = true }
            guard started, !key.isEmpty, !value.isEmpty else { continue }
            fields.append(.init(key: key, value: value))
        }
        guard !fields.isEmpty else { return nil }

        func field(_ predicate: (String) -> Bool) -> String? {
            fields.first { predicate($0.key.lowercased()) }?.value
        }
        let name = field { $0 == "name" } ?? fallbackName
        let memory = field { $0.contains("memory") }.flatMap(parseSize)
        let package = field { $0 == "package" }
        return DeviceInfo(
            name: name,
            fields: fields.filter { $0.key.lowercased() != "name" },
            memoryBytes: memory,
            package: package
        )
    }

    /// Main memory size in bytes from minipro's `Memory:` field.
    ///
    /// minipro lists several areas joined with "+", e.g. "32768 Bytes",
    /// "2048 Words + 128 Bytes" (PIC code + EEPROM) or "0 Bytes + 131102 Bytes"
    /// (NAND). The image ZIFburn reads/writes is the first non-empty area,
    /// so that is what gets returned; words count as 2 bytes.
    static func parseSize(_ s: String) -> Int? {
        let ns = s as NSString
        for match in sizeTerm.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            let unit = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2)).lowercased()
            let value = raw.lowercased().hasPrefix("0x") ? Int(raw.dropFirst(2), radix: 16) : Int(raw)
            guard let value, value > 0 else { continue }
            return unit.hasPrefix("word") ? value * 2 : value
        }
        return nil
    }

    private static func lastCapture(_ regex: NSRegularExpression, in s: String, first: Bool = false) -> String? {
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard let m = first ? matches.first : matches.last else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

/// minipro's database contains a few names whose Chinese full-width
/// parentheses were mis-encoded at some point ("£¨GSTO)…" is "（GSTO)…" in
/// GBK read as Latin-1). The raw name must still be passed to minipro
/// unchanged; this only repairs what is shown, searched and sorted.
enum DeviceName {
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    static func display(_ raw: String) -> String {
        guard raw.unicodeScalars.contains(where: { $0.value >= 0x80 }) else { return raw }
        var text = raw
        if let bytes = raw.data(using: .isoLatin1), let repaired = String(data: bytes, encoding: gb18030) {
            text = repaired
        }
        return text
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
    }
}
