import SwiftUI

/// Shows where the selected chip goes in the programmer's ZIF socket
/// (Xgpro's "Information" diagram), drawn as you hold the programmer with
/// the USB connector at the top.
@MainActor
struct ZIFDiagram: View {
    @Environment(\.theme) private var theme
    let socket: SocketLayout
    let package: String?
    enum Mount: Equatable {
        /// Chip goes straight into the socket.
        case direct
        /// SMD chip on a breakout board, e.g. "SOIC8" on a SOIC8 → DIP8 adapter.
        case smd(String)
        /// A named adapter board, e.g. the 27C160/322/400/800 adapter.
        case board(String)
    }

    var mount: Mount = .direct

    var body: some View {
        let placement = ChipPlacement(package: package, socket: socket)

        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                ZIFRenderer.draw(in: &ctx, size: size, socket: socket, placement: placement, onAdapter: mount != .direct)
            }
            .frame(height: socket.pins == 48 ? 290 : 260)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(caption(placement))

            Text(caption(placement))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Drawn with the USB connector at the top. If in doubt, follow the diagram printed on the programmer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(_ placement: ChipPlacement?) -> String {
        guard let package else { return "Select a chip to see where it goes in the \(socket.modelName) socket." }
        guard let placement else {
            return "\(package) doesn't fit the \(socket.pins)-pin ZIF socket directly – it needs an adapter."
        }
        let orientation = socket.notchUp
            ? "notch up, pin 1 top-left"
            : "notch down towards the lever, pin 1 bottom-right"
        let end = socket.chipAtBottom == socket.leverBottomRight ? "lever end" : "end away from the lever"
        let where_ = placement.chipPins == socket.pins
            ? "filling the whole socket"
            : "pushed to the \(end) of the socket"
        let dip = "\(Self.article(placement.chipPins)) \(placement.chipPins)-pin DIP"
        switch mount {
        case .direct:
            break
        case .smd(let smd):
            return "\(smd) chip: solder or clamp it onto a \(smd) → DIP\(placement.chipPins) adapter, then put the adapter in the \(socket.modelName) like \(dip) – \(orientation), \(where_)."
        case .board(let name):
            return "\(name): put the chip in the adapter, then the adapter in the \(socket.modelName) like \(dip) – \(orientation), \(where_)."
        }
        return "\(placement.chipPins)-pin DIP on the \(socket.modelName): \(orientation), \(where_)."
    }
}

extension ZIFDiagram {
    /// "an 8-pin", "an 18-pin", "a 28-pin".
    static func article(_ n: Int) -> String {
        let text = String(n)
        return text.hasPrefix("8") || text == "11" || text == "18" ? "an" : "a"
    }
}

/// Pure drawing code, kept off the main actor for Canvas.
enum ZIFRenderer {
    static let socketColor = Color(hex: 0x1F7A6B)
    static let holeColor = Color(hex: 0x0C3F35)
    static let chipColor = Color(hex: 0x22252B)
    static let pinColor = Color(hex: 0xD9D4C7)
    static let leverColor = Color(hex: 0xA9ADB6)
    static let adapterColor = Color(hex: 0x2B4C8C)   // adapter PCB blue

    static func draw(in ctx: inout GraphicsContext, size: CGSize, socket: SocketLayout,
                     placement: ChipPlacement?, onAdapter: Bool = false) {
        let rows = socket.pins / 2
        let bodyWidth: CGFloat = 112
        let body = CGRect(x: (size.width - bodyWidth) / 2, y: 12, width: bodyWidth, height: size.height - 24)

        // USB connector hint above the socket.
        let usb = CGRect(x: body.midX - 14, y: 0, width: 28, height: 8)
        ctx.fill(Path(roundedRect: usb, cornerRadius: 2), with: .color(leverColor.opacity(0.6)))
        ctx.draw(Text("USB").font(.system(size: 8, weight: .semibold)), at: CGPoint(x: body.midX + 34, y: 4))

        ctx.fill(Path(roundedRect: body, cornerRadius: 8), with: .color(socketColor))

        let inset: CGFloat = 8
        let rowHeight = (body.height - inset * 2) / CGFloat(rows)
        let hole = min(rowHeight * 0.6, 7)
        let leftX = body.minX + 18
        let rightX = body.maxX - 18

        if let placement {
            let chipRows = CGFloat(placement.chipPins / 2)
            let chip = CGRect(
                x: leftX - 7,
                y: body.minY + inset + CGFloat(placement.firstRow) * rowHeight + 1,
                width: rightX - leftX + 14,
                height: chipRows * rowHeight - 2
            )
            ctx.fill(Path(roundedRect: chip, cornerRadius: 3), with: .color(onAdapter ? adapterColor : chipColor))
            if onAdapter {
                let smd = chip.insetBy(dx: chip.width * 0.28, dy: max(chip.height * 0.28, 4))
                ctx.fill(Path(roundedRect: smd, cornerRadius: 2), with: .color(chipColor))
            }
            // Notch on the top or bottom edge, and the pin-1 dot next to it.
            let notchY = socket.notchUp ? chip.minY : chip.maxY
            ctx.fill(Path(ellipseIn: CGRect(x: chip.midX - 6, y: notchY - 6, width: 12, height: 12)),
                     with: .color(socketColor))
            let dot = socket.notchUp
                ? CGRect(x: chip.minX + 10, y: chip.minY + 5, width: 5, height: 5)
                : CGRect(x: chip.maxX - 15, y: chip.maxY - 10, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.75)))
        }

        for row in 0..<rows {
            let y = body.minY + inset + (CGFloat(row) + 0.5) * rowHeight
            let used = placement.map { row >= $0.firstRow && row < $0.firstRow + $0.chipPins / 2 } ?? false
            for x in [leftX, rightX] {
                let rect = CGRect(x: x - hole / 2, y: y - hole / 2, width: hole, height: hole)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(used ? pinColor : holeColor))
            }
        }

        // "1" beside pin 1: left column when the notch is up, right column when down.
        if let placement {
            let row = placement.pin1Row(notchUp: socket.notchUp)
            let y = body.minY + inset + (CGFloat(row) + 0.5) * rowHeight
            let x = socket.notchUp ? body.minX - 26 : body.maxX + 30
            ctx.draw(Text("1").font(.system(size: 10, weight: .bold, design: .monospaced)), at: CGPoint(x: x, y: y))
        }

        // Lever with its knob.
        let leverLength = body.height * 0.62
        let lever: CGRect
        let knobY: CGFloat
        if socket.leverBottomRight {
            lever = CGRect(x: body.maxX + 7, y: body.maxY - 12 - leverLength, width: 6, height: leverLength)
            knobY = lever.maxY
        } else {
            lever = CGRect(x: body.minX - 13, y: body.minY + 12, width: 6, height: leverLength)
            knobY = lever.minY
        }
        ctx.fill(Path(roundedRect: lever, cornerRadius: 3), with: .color(leverColor))
        ctx.fill(Path(ellipseIn: CGRect(x: lever.midX - 7, y: knobY - 7, width: 14, height: 14)),
                 with: .color(leverColor))
    }
}
