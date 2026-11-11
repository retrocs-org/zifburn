import AppKit
import SwiftUI

@MainActor
struct DetailView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // The target bar always keeps its natural height; the split view
            // below takes whatever is left, so nothing gets pushed off-screen.
            TargetBar()
                .layoutPriority(1)
            Divider()
            VSplitView {
                BufferPane()
                    .frame(minHeight: 160, idealHeight: 420, maxHeight: .infinity)
                LogView()
                    .frame(minHeight: 80, idealHeight: 190, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            SuggestionBanner()
            Divider()
            StatusBar()
        }
        .background(theme.palette?.background ?? Color.clear)
    }
}

@MainActor
struct BufferPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let buffer = model.buffer {
                HexView(buffer: buffer)
            } else {
                ContentUnavailableView {
                    Label("Empty Buffer", systemImage: "square.grid.3x3.square")
                } description: {
                    Text("Read a chip, or drop a .bin or .hex file here.")
                } actions: {
                    Button("Open Image…") { model.openFile() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.loadFile(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }
}

/// Plain-language advice for the last failure, with a one-click fix when safe.
@MainActor
struct SuggestionBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        if let suggestion = model.suggestion, model.activity == nil {
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(theme.warning)
                    Text(suggestion.hint)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let label = suggestion.actionLabel {
                        Button(label) { Task { await model.applySuggestion() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(model.isBusy)
                    }
                    Button { model.dismissSuggestion() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.warning.opacity(0.12))
            }
        }
    }
}

@MainActor
struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let activity = model.activity {
                if let progress = activity.progress {
                    ProgressView(value: progress)
                        .frame(width: 140)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(activity.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if activity.stages > 1 {
                    Text("step \(min(activity.stageIndex + 1, activity.stages)) of \(activity.stages)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(activity.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button("Cancel") { model.cancel() }
                    .controlSize(.small)
            } else if let outcome = model.lastOutcome {
                Image(systemName: outcome.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(outcome.success ? theme.success : theme.error)
                Text(outcome.message)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(outcome.message)
                Text(outcome.date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                Text("Ready")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let version = model.miniproVersion {
                Text("minipro \(version)")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(theme.palette?.sidebar ?? Color.clear)
        .background(.bar)
    }
}
