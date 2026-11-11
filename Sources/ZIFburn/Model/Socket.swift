import Foundation

/// The ZIF socket of each programmer family, drawn as you hold the
/// programmer with its USB connector at the top.
///
/// TL866A/CS and TL866II+ are verified against the real hardware: lever at
/// the bottom-right, chips pushed to the lever end, notch towards the lever
/// (the "IC ↓" icon printed on the case) – i.e. pin 1 next to the handle.
/// T48/T56/T76 follow community documentation.
struct SocketLayout: Equatable {
    let modelName: String
    /// ZIF socket size.
    let pins: Int
    /// Lever at the bottom-right, else top-left.
    let leverBottomRight: Bool
    /// Chips are pushed to the bottom end of the socket, else the top.
    let chipAtBottom: Bool
    /// Chip notch points up (pin 1 top-left), else down (pin 1 bottom-right).
    let notchUp: Bool

    static func forProgrammer(_ q: String?) -> SocketLayout {
        switch q {
        case "t48":
            SocketLayout(modelName: "T48", pins: 40, leverBottomRight: true, chipAtBottom: false, notchUp: true)
        case "t56":
            SocketLayout(modelName: "T56", pins: 48, leverBottomRight: false, chipAtBottom: true, notchUp: true)
        case "t76":
            SocketLayout(modelName: "T76", pins: 48, leverBottomRight: false, chipAtBottom: true, notchUp: true)
        case "tl866a":
            SocketLayout(modelName: "TL866A/CS", pins: 40, leverBottomRight: true, chipAtBottom: true, notchUp: false)
        default:
            SocketLayout(modelName: "TL866II+", pins: 40, leverBottomRight: true, chipAtBottom: true, notchUp: false)
        }
    }
}

/// Chips listed as "NAME@SOIC8", "NAME@DFN8", "NAME@PLCC32" … that minipro
/// still reports as a DIP footprint go into the socket on an adapter.
/// Returns the chip's real package ("DFN8") in that case, else nil.
func adapterPackage(device: String?, reportedPackage: String?) -> String? {
    guard let device, let at = device.lastIndex(of: "@"),
          let reported = reportedPackage, reported.uppercased().hasPrefix("DIP")
    else { return nil }
    let variant = String(device[device.index(after: at)...])
    guard !variant.isEmpty, !variant.uppercased().hasPrefix("DIP") else { return nil }
    return variant
}

/// Where a DIP chip goes in the socket. nil = not a DIP that fits (needs an adapter).
struct ChipPlacement: Equatable {
    let chipPins: Int
    /// Top socket row (0 = top) the chip occupies.
    let firstRow: Int

    /// Socket row of chip pin 1 (top row when the notch points up, else bottom row).
    func pin1Row(notchUp: Bool) -> Int {
        notchUp ? firstRow : firstRow + chipPins / 2 - 1
    }

    init?(package: String?, socket: SocketLayout) {
        guard let package else { return nil }
        let upper = package.uppercased()
        guard upper.hasPrefix("DIP"),
              let pins = Int(upper.dropFirst(3).prefix { $0.isNumber }),
              pins >= 4, pins % 2 == 0, pins <= socket.pins
        else { return nil }
        chipPins = pins
        firstRow = socket.chipAtBottom ? socket.pins / 2 - pins / 2 : 0
    }
}
