import AppKit
import SwiftUI

@MainActor
struct HexView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @AppStorage(DefaultsKey.hexFontSize) private var fontSize = 12.0
    let buffer: ChipBuffer

    @State private var gotoText = ""
    @State private var findText = ""
    @State private var findAsHex = true
    @State private var highlightedRow: Int?
    @State private var markIndex = -1
    @FocusState private var findFocused: Bool

    private var rowCount: Int { (buffer.data.count + 15) / 16 }
    private var addressDigits: Int { buffer.data.count > 0x10000 ? 8 : 4 }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                toolbar(proxy)
                Divider()
                columnHeader
                List(0..<rowCount, id: \.self) { row in
                    HexRowView(
                        row: HexFormatter.row(buffer.data, row: row, addressDigits: addressDigits),
                        marks: model.marks?.indexes,
                        markColor: markColor,
                        fontSize: fontSize
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowBackground(row == highlightedRow ? theme.accent.opacity(0.18) : Color.clear)
                }
                .listStyle(.plain)
                .themedBackground(theme, nil)
                .environment(\.defaultMinListRowHeight, fontSize + 5)
            }
            .onChange(of: buffer.id) { _, _ in highlightedRow = nil }
            .onChange(of: model.marks) { _, marks in
                markIndex = -1
                if let first = marks?.anchors.first {
                    markIndex = 0
                    jump(to: first, proxy)
                }
            }
        }
    }

    // MARK: Header: title + stats

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(buffer.title)
                        .font(.headline)
                        .lineLimit(1)
                    if buffer.modified {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.warning.opacity(0.25)))
                    }
                }
                Text(buffer.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(minWidth: 140, alignment: .leading)

            Divider().frame(height: 28)

            stat("Size", AppModel.size(buffer.data.count))
            if let stats = model.bufferStats {
                stat("CRC32", String(format: "%08X", stats.crc32))
                stat("Sum16", String(format: "%04X", stats.sum16))
                if let fill = stats.uniformByte {
                    stat("Content", String(format: "all $%02X", fill))
                }
            } else {
                ProgressView().controlSize(.small)
            }

            if model.bufferSizeMismatch, let expected = model.deviceInfo?.memoryBytes {
                Label("Chip is \(AppModel.size(expected))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(theme.warning)
                    .help("The buffer size differs from the selected chip's capacity.")
            }

            Spacer(minLength: 8)

            if !buffer.extraFiles.isEmpty {
                Button { model.revealExtraFiles() } label: {
                    Label("\(buffer.extraFiles.count) more", systemImage: "doc.on.doc")
                }
                .help("minipro produced additional files (EEPROM / fuses). Show them in Finder.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Toolbar: find, compare, trim/pad, marks, go to

    private func toolbar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(findAsHex ? "DE AD BE EF" : "Text to find", text: $findText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: findAsHex ? .monospaced : .default))
                    .frame(width: 180)
                    .focused($findFocused)
                    .help(findAsHex ? "Find a byte pattern (⌘F), e.g. DE AD BE EF" : "Find text (⌘F)")
                    .onSubmit { model.find(findText, asHex: findAsHex) }
                Picker("Find mode", selection: $findAsHex) {
                    Text("Hex").tag(true)
                    Text("Text").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
                // ⌘F focuses the find field.
                Button("") { findFocused = true }
                    .keyboardShortcut("f")
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }

            Button { Task { await model.compareWithFile() } } label: {
                Label("Compare…", systemImage: "arrow.left.arrow.right")
            }
            .help("Highlight every byte that differs from an image file")

            Menu {
                Button("Trim Trailing $FF") { model.trimBuffer(fill: 0xFF) }
                Button("Trim Trailing $00") { model.trimBuffer(fill: 0x00) }
                Divider()
                Button("Pad to Chip Size with $FF") { model.padBuffer(fill: 0xFF) }
                    .disabled(!model.canPadBuffer)
                Button("Pad to Chip Size with $00") { model.padBuffer(fill: 0x00) }
                    .disabled(!model.canPadBuffer)
                Divider()
                Button("Swap Byte Order (16-bit)") { model.swapBufferBytes() }
            } label: {
                Label("Trim / Pad", systemImage: "arrow.left.and.right.square")
            }
            .fixedSize()
            .help("Strip unused fill bytes, or pad the image to the chip's size")

            if let marks = model.marks {
                marksNavigator(marks, proxy)
            }

            Spacer(minLength: 8)

            TextField("Go to $offset", text: $gotoText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120)
                .onSubmit { goTo(proxy) }
                .help("Hex offset, e.g. 1FF0, $1FF0 or 0x1FF0")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func marksNavigator(_ marks: ByteMarks, _ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 4) {
            Image(systemName: markIcon(marks.kind))
                .foregroundStyle(markColor)
            Text(marks.anchors.isEmpty || markIndex < 0
                 ? marks.title
                 : "\(markIndex + 1)/\(marks.anchors.count) · \(marks.title)")
                .font(.caption)
                .lineLimit(1)
            Button { step(-1, marks, proxy) } label: { Image(systemName: "chevron.up") }
                .disabled(marks.anchors.isEmpty)
                .help("Previous")
            Button { step(1, marks, proxy) } label: { Image(systemName: "chevron.down") }
                .disabled(marks.anchors.isEmpty)
                .help("Next")
            Button { model.clearMarks() } label: { Image(systemName: "xmark.circle.fill") }
                .foregroundStyle(.secondary)
                .help("Clear highlights")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(markColor.opacity(0.15)))
    }

    private var markColor: Color {
        switch model.marks?.kind {
        case .diff: theme.error
        case .unstable: theme.warning
        case .find, .none: theme.accent
        }
    }

    private func markIcon(_ kind: ByteMarks.Kind) -> String {
        switch kind {
        case .find: "magnifyingglass"
        case .diff: "arrow.left.arrow.right"
        case .unstable: "waveform.path.ecg"
        }
    }

    private var columnHeader: some View {
        HexRowView(
            row: HexFormatter.Row(
                address: String(repeating: " ", count: addressDigits),
                hex: "00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F ",
                ascii: "0123456789ABCDEF"
            ),
            marks: nil,
            markColor: .clear,
            fontSize: fontSize
        )
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    // MARK: Navigation

    private func step(_ delta: Int, _ marks: ByteMarks, _ proxy: ScrollViewProxy) {
        guard !marks.anchors.isEmpty else { return }
        let count = marks.anchors.count
        markIndex = ((markIndex < 0 ? (delta > 0 ? -1 : 0) : markIndex) + delta + count) % count
        jump(to: marks.anchors[markIndex], proxy)
    }

    private func goTo(_ proxy: ScrollViewProxy) {
        var text = gotoText.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("0x") { text.removeFirst(2) } else if text.hasPrefix("$") { text.removeFirst() }
        guard let offset = Int(text, radix: 16), offset >= 0, offset < buffer.data.count else {
            NSSound.beep()
            return
        }
        jump(to: offset, proxy)
    }

    private func jump(to offset: Int, _ proxy: ScrollViewProxy) {
        let row = offset / 16
        highlightedRow = row
        withAnimation { proxy.scrollTo(row, anchor: .center) }
    }
}

@MainActor
struct HexRowView: View {
    let row: HexFormatter.Row
    let marks: IndexSet?
    let markColor: Color
    let fontSize: Double

    var body: some View {
        HStack(spacing: 18) {
            Text(row.address)
                .foregroundStyle(.secondary)
            hexText
            asciiText
                .foregroundStyle(.secondary)
        }
        .font(.system(size: fontSize, design: .monospaced))
        .lineLimit(1)
        .fixedSize()
    }

    /// Only rows that contain highlighted bytes pay for per-byte Text runs.
    private var rowMarks: IndexSet? {
        guard let marks, !row.bytes.isEmpty,
              marks.intersects(integersIn: row.start..<(row.start + row.bytes.count))
        else { return nil }
        return marks
    }

    private var hexText: Text {
        guard let marks = rowMarks else { return Text(verbatim: row.hex) }
        var text = Text(verbatim: "")
        for (i, byte) in row.bytes.enumerated() {
            if i == 8 { text = text + Text(verbatim: " ") }
            let cell = Text(verbatim: HexFormatter.byte(byte) + " ")
            text = text + (marks.contains(row.start + i) ? cell.foregroundColor(markColor).bold() : cell)
        }
        let missing = 16 - row.bytes.count
        if missing > 0 {
            text = text + Text(verbatim: String(repeating: "   ", count: missing) + (row.bytes.count <= 8 ? " " : ""))
        }
        return text
    }

    private var asciiText: Text {
        guard let marks = rowMarks else { return Text(verbatim: row.ascii) }
        var text = Text(verbatim: "")
        for (i, byte) in row.bytes.enumerated() {
            let cell = Text(verbatim: HexFormatter.asciiChar(byte))
            text = text + (marks.contains(row.start + i) ? cell.foregroundColor(markColor).bold() : cell)
        }
        return text
    }
}
