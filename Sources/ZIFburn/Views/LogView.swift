import SwiftUI

@MainActor
struct LogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Console", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { model.copyLastCommand() } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .help("Copy the last minipro command line")
                .disabled(model.lastCommand == nil)
                Button { model.copyLog() } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy the console")
                Button { model.clearLog() } label: {
                    Image(systemName: "trash")
                }
                .help("Clear the console")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                List(model.log) { entry in
                    LogRow(entry: entry)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .id(entry.id)
                }
                .listStyle(.plain)
                .themedBackground(theme, nil)
                .environment(\.defaultMinListRowHeight, 16)
                .onChange(of: model.log.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }
}

@MainActor
struct LogRow: View {
    @Environment(\.theme) private var theme
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .foregroundStyle(.tertiary)
            Text(entry.text)
                .foregroundStyle(entry.kind.color(in: theme))
                .fontWeight(entry.kind == .command ? .semibold : .regular)
                .textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
