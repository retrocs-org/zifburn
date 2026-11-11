import Foundation

/// A ZIF adapter board that lets the programmer handle chips minipro can't
/// drive directly, by presenting them as another device, one bank at a time.
struct AdapterProfile: Identifiable, Equatable {
    struct Target: Identifiable, Hashable {
        /// Chip family name, e.g. "27C800".
        let id: String
        /// Number of banks (powers of two), each `bankSize` bytes.
        let banks: Int
        /// Required position of the adapter's slide switch.
        let modeSwitch: String
    }

    let id: String
    let name: String
    /// minipro device each bank is read/written as.
    let device: String
    /// Bytes per bank.
    let bankSize: Int
    /// DIP switches that select the bank, lowest address bit first.
    let switchLabels: [String]
    let targets: [Target]
    /// Documented switch polarity: true = ON drives the address line high.
    let defaultOnMeansHigh: Bool
    /// How the adapter and chip go into the programmer.
    let insertion: String
    /// Practical tips shown when a bank fails.
    let troubleshooting: String
    /// Settings the adapter's guide recommends for the stand-in device.
    let guidePulse: Int?
    let guideVPP: Double?

    func size(of target: Target) -> Int { bankSize * target.banks }

    /// Number of bank-select switches a target needs (log2 of its banks).
    static func bits(for banks: Int) -> Int {
        var n = 0
        while (1 << n) < banks { n += 1 }
        return n
    }

    /// Switch states (true = ON) for a bank. Switches the target doesn't use
    /// are set to "address low".
    func switches(bank: Int, target: Target, onMeansHigh: Bool) -> [Bool] {
        let used = Self.bits(for: target.banks)
        return switchLabels.indices.map { i in
            let high = i < used && (bank >> i) & 1 == 1
            return onMeansHigh ? high : !high
        }
    }

    /// "Part 003" – the naming used by the adapter's DIP table (and HJSplit's .001 files).
    static func partName(_ bank: Int) -> String { String(format: "Part %03d", bank + 1) }

    /// "DIP 1 (A18) ON, 2 (A19) OFF, 3 (A20) OFF · slide switch on “other”"
    func describe(bank: Int, target: Target, onMeansHigh: Bool) -> String {
        let states = switches(bank: bank, target: target, onMeansHigh: onMeansHigh)
        let dip = switchLabels.indices.map { i in
            "\(i + 1) (\(switchLabels[i])) \(states[i] ? "ON" : "OFF")"
        }.joined(separator: ", ")
        return "DIP \(dip) · slide switch on “\(target.modeSwitch)”"
    }
}

extension AdapterProfile {
    /// mafe72's open-source "27c160/322/400/800 Adapter"
    /// (github.com/mafe72/27c160-tl866-adapter): a 40/42-pin 16-bit EPROM is
    /// programmed as an AM27C4096 in 512 KB banks. DIP switches 1–3 drive
    /// A18–A20 – per the official table, ON = address bit 0 (Part 001 = all
    /// ON, Part 008 = all OFF). The slide switch selects 27C322 mode.
    static let eprom16 = AdapterProfile(
        id: "27c160-322-400-800",
        name: "27C160/322/400/800 adapter",
        device: "AM27C4096@DIP40",
        bankSize: 512 * 1024,
        switchLabels: ["A18", "A19", "A20"],
        targets: [
            Target(id: "27C400", banks: 1, modeSwitch: "other"),
            Target(id: "27C800", banks: 2, modeSwitch: "other"),
            Target(id: "27C160", banks: 4, modeSwitch: "other"),
            Target(id: "27C322", banks: 8, modeSwitch: "27c322"),
        ],
        defaultOnMeansHigh: false,
        insertion: "Put the adapter in the programmer with the two levers next to each other, then the EPROM in the lowest position of the adapter's socket with pin 1 nearest its lever. A 40-pin 27C400 leaves the top two contacts free.",
        troubleshooting: "Blank-check first – pulled EPROMs are often not fully erased (10–20 min of UV). Open and close the adapter's lever a few times and reseat the chip squarely in the lowest position, and check the switches against the table. If writes still fail, raise VPP towards 13–13.5 V, or try a 100 µs pulse for stubborn 27C160s (Inspector › Programming voltages).",
        guidePulse: 50,
        guideVPP: 12.5
    )

    static let all: [AdapterProfile] = [.eprom16]
}

/// A bank-by-bank job through an adapter.
struct AdapterJob: Hashable {
    enum Kind: String {
        case read, burn, verify, blankCheck
    }

    let kind: Kind
    let targetID: String
    let banks: Int
    /// Burn/verify: one image slice per bank.
    let bankFiles: [URL]
}
