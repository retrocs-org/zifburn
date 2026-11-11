import Foundation

enum ChipOperation: Hashable {
    case read, write, verify, blankCheck, erase, readID, pinCheck, logicTest
}

enum MemoryPage: String, CaseIterable, Identifiable, Codable {
    case auto, code, data, config, user, calibration
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Default"
        case .code: "Code"
        case .data: "Data (EEPROM)"
        case .config: "Config / Fuses"
        case .user: "User"
        case .calibration: "Calibration"
        }
    }
}

enum ICSPMode: String, CaseIterable, Identifiable, Codable {
    case off, withVCC, withoutVCC
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off (use socket)"
        case .withVCC: "ICSP, programmer supplies VCC"
        case .withoutVCC: "ICSP, target is self-powered"
        }
    }
}

/// The steps minipro accepts (from `man minipro`, version 0.7.4).
enum VoltageTable {
    static let vppTL866A: [Double] = [10, 12.5, 13.5, 14, 15.5, 16, 17, 18, 21]
    static let vppTL866II: [Double] = [9, 9.5, 10, 11, 11.5, 12, 12.5, 13, 13.5, 14, 14.5, 15.5, 16, 16.5, 17, 19]
    /// VDD write and VCC verify.
    static let vddVcc: [Double] = [3.3, 4, 4.5, 5, 5.5, 6.5]
    /// Common pulse delays in µs (minipro accepts 0–65535).
    static let pulses: [Int] = [25, 50, 100, 200, 300, 500, 1000]

    static func vpp(forTL866A: Bool) -> [Double] { forTL866A ? vppTL866A : vppTL866II }

    /// 12.5 → "12.5", 13 → "13", 3.3 → "3.3".
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Every user-facing switch maps to exactly one minipro flag, and each flag is
/// only passed to the operations where it means something.
struct ProgrammingOptions: Codable, Equatable {
    var page: MemoryPage = .auto
    var skipErase = false          // -e
    var skipVerify = false         // -v
    var noProtectOff = false       // -u
    var noProtectOn = false        // -P
    var skipIDCheck = false        // -x
    var ignoreIDError = false      // -y
    var ignoreSizeError = false    // -s
    var ignoreSizeWarning = false  // -S
    var icsp: ICSPMode = .off      // -i / -I
    var pinCheckFirst = true       // run -z before operations (TL866II+/T48)
    // Programming voltages / pulse (nil = chip default). minipro applies these
    // only in write mode, and only to UV EPROMs and GAL/ATF PLDs.
    var vpp: Double?               // -o vpp=
    var vdd: Double?               // -o vdd=  (VDD write)
    var vcc: Double?               // -o vcc=  (VCC verify)
    var pulse: Int?                // -o pulse= (µs)

    var hasVoltageOverrides: Bool { vpp != nil || vdd != nil || vcc != nil || pulse != nil }

    init() {}

    // Decode tolerantly so options saved by older builds keep working
    // when new switches are added.
    enum CodingKeys: String, CodingKey {
        case page, skipErase, skipVerify, noProtectOff, noProtectOn, skipIDCheck,
             ignoreIDError, ignoreSizeError, ignoreSizeWarning, icsp, pinCheckFirst,
             vpp, vdd, vcc, pulse
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decodeIfPresent(MemoryPage.self, forKey: .page) ?? .auto
        skipErase = try c.decodeIfPresent(Bool.self, forKey: .skipErase) ?? false
        skipVerify = try c.decodeIfPresent(Bool.self, forKey: .skipVerify) ?? false
        noProtectOff = try c.decodeIfPresent(Bool.self, forKey: .noProtectOff) ?? false
        noProtectOn = try c.decodeIfPresent(Bool.self, forKey: .noProtectOn) ?? false
        skipIDCheck = try c.decodeIfPresent(Bool.self, forKey: .skipIDCheck) ?? false
        ignoreIDError = try c.decodeIfPresent(Bool.self, forKey: .ignoreIDError) ?? false
        ignoreSizeError = try c.decodeIfPresent(Bool.self, forKey: .ignoreSizeError) ?? false
        ignoreSizeWarning = try c.decodeIfPresent(Bool.self, forKey: .ignoreSizeWarning) ?? false
        icsp = try c.decodeIfPresent(ICSPMode.self, forKey: .icsp) ?? .off
        pinCheckFirst = try c.decodeIfPresent(Bool.self, forKey: .pinCheckFirst) ?? true
        vpp = try c.decodeIfPresent(Double.self, forKey: .vpp)
        vdd = try c.decodeIfPresent(Double.self, forKey: .vdd)
        vcc = try c.decodeIfPresent(Double.self, forKey: .vcc)
        pulse = try c.decodeIfPresent(Int.self, forKey: .pulse)
    }

    func arguments(for op: ChipOperation) -> [String] {
        var args: [String] = []
        let touchesMemory = op != .pinCheck && op != .logicTest

        if touchesMemory {
            if skipIDCheck { args.append("-x") }
            if ignoreIDError { args.append("-y") }
            switch icsp {
            case .off: break
            case .withVCC: args.append("-i")
            case .withoutVCC: args.append("-I")
            }
        }
        if op == .read || op == .write || op == .verify, page != .auto {
            args += ["-c", page.rawValue]
        }
        if op == .write {
            if let vpp { args += ["-o", "vpp=" + VoltageTable.format(vpp)] }
            if let vdd { args += ["-o", "vdd=" + VoltageTable.format(vdd)] }
            if let vcc { args += ["-o", "vcc=" + VoltageTable.format(vcc)] }
            if let pulse { args += ["-o", "pulse=\(pulse)"] }
            if skipErase { args.append("-e") }
            if skipVerify { args.append("-v") }
            if noProtectOff { args.append("-u") }
            if noProtectOn { args.append("-P") }
        }
        if op == .write || op == .verify {
            if ignoreSizeError { args.append("-s") }
            if ignoreSizeWarning { args.append("-S") }
        }
        return args
    }
}
