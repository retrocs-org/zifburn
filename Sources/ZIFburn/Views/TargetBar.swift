import AppKit
import SwiftUI

/// Top of the window: programmer + chip select boxes, favourite star, and the
/// parsed `minipro -d` info for the selected chip.
@MainActor
struct TargetBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "memorychip")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Programmer", selection: $model.database) {
                        ForEach(DeviceDatabase.allCases) { db in
                            let unsupported = model.unsupportedDatabases.contains(db)
                            Text(label(for: db) + (unsupported ? " – needs newer minipro" : ""))
                                .tag(db)
                                .disabled(unsupported)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 230)
                    .help("Which chip database to show. Auto follows the connected programmer.")

                    ChipPicker()

                    if let name = model.selectedDevice {
                        let favorite = model.isFavorite(name)
                        Button { model.toggleFavorite(name) } label: {
                            Image(systemName: favorite ? "star.fill" : "star")
                                .foregroundStyle(favorite ? theme.warning : theme.secondaryText)
                        }
                        .buttonStyle(.borderless)
                        .help(favorite ? "Remove from favorites" : "Add to favorites")
                    }
                    Spacer(minLength: 0)
                }

                infoGrid

                if let warning = model.packageVariantWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(theme.warning)
                        .lineLimit(2)
                        .help(warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var infoGrid: some View {
        if let info = model.deviceInfo {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 16, alignment: .leading)],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(Array(info.fields.enumerated()), id: \.offset) { _, field in
                    HStack(spacing: 4) {
                        Text(field.key + ":")
                            .foregroundStyle(.secondary)
                        Text(field.value)
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                    .lineLimit(1)
                }
            }
        } else if let error = model.deviceInfoError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(theme.warning)
                .lineLimit(2)
        } else if model.selectedDevice != nil {
            Text("Loading chip info…")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("Choose a chip (⌘L), or use Tools › Auto-detect for SPI flash.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func label(for db: DeviceDatabase) -> String {
        guard db == .auto else { return db.label }
        return model.programmer.isConnected ? "Auto – \(model.programmer.title)" : "Auto – all databases"
    }
}

// MARK: - Chip select box

/// Looks like a pop-up button; opens a searchable dropdown, because a plain
/// menu with ~28 000 chips would be unusable.
@MainActor
struct ChipPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model

        Button { model.chipPickerOpen.toggle() } label: {
            HStack(spacing: 8) {
                Text(model.selectedDevice.map(DeviceName.display) ?? "Select a chip…")
                    .foregroundStyle(model.selectedDevice == nil ? theme.secondaryText : theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.palette?.surface ?? Color.secondary.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Choose the chip in the socket (⌘L)")
        .popover(isPresented: $model.chipPickerOpen, arrowEdge: .bottom) {
            ChipPickerList()
                .environment(model)
                .environment(\.theme, theme)
                .tint(theme.accent)
                .foregroundStyle(theme.textStyle)
                .background(theme.palette?.background ?? Color.clear)
                .frame(width: 440, height: 480)
        }
    }
}

// MARK: - Dropdown contents

@MainActor
struct ChipPickerList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    @State private var query = ""
    @State private var highlighted: String?
    @State private var scrollTarget: String?
    @FocusState private var searchFocused: Bool

    private struct Row: Identifiable, Hashable {
        let section: String
        let name: String
        var id: String { section + "\u{1}" + name }
    }

    private struct RowSection {
        let title: String
        let rows: [Row]
    }

    var body: some View {
        let results = model.searchDevices(query)
        let sections = makeSections(results.names)

        VStack(spacing: 0) {
            searchField(sections)
            Divider()

            ScrollViewReader { proxy in
                List {
                    ForEach(sections, id: \.title) { section in
                        // Header as an ordinary row: SwiftUI's sticky section
                        // headers get a grey material that clashes with themes.
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.top, 8)
                            .padding(.leading, 6)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        ForEach(section.rows) { row in
                            rowView(row)
                                .id(row.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        }
                    }
                    if results.truncated {
                        Text("Showing the first \(AppModel.deviceListLimit) – keep typing to narrow it down.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .themedBackground(theme, nil)
                .onChange(of: scrollTarget) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            .overlay { emptyState(results.names.isEmpty) }

            Divider()
            footer
        }
        .onAppear {
            searchFocused = true
            highlighted = sections.flatMap(\.rows).first { $0.name == model.selectedDevice }?.id
                ?? sections.first?.rows.first?.id
        }
        .onChange(of: query) { _, _ in
            let rows = makeSections(model.searchDevices(query).names).flatMap(\.rows)
            highlighted = rows.first?.id
            scrollTarget = rows.first?.id
        }
    }

    private func searchField(_ sections: [RowSection]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search chips, e.g. 27C512 DIP", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { commit(sections) }
                .onKeyPress(.downArrow) { move(1, in: sections); return .handled }
                .onKeyPress(.upArrow) { move(-1, in: sections); return .handled }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 6) {
            Text(DeviceName.display(row.name))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if model.isFavorite(row.name) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.warning)
            }
            if row.name == model.selectedDevice {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(row.id == highlighted ? theme.accent.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { choose(row.name) }
        .onHover { inside in if inside { highlighted = row.id } }
        .contextMenu {
            Button(model.isFavorite(row.name) ? "Remove from Favorites" : "Add to Favorites") {
                model.toggleFavorite(row.name)
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.name, forType: .string)
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ noResults: Bool) -> some View {
        if model.allDevices.isEmpty {
            if model.isLoadingDevices {
                ProgressView("Loading chip list…")
            } else {
                ContentUnavailableView(
                    "No Chips",
                    systemImage: "memorychip",
                    description: Text("minipro returned no devices – see the console.")
                )
            }
        } else if !query.isEmpty && noResults {
            ContentUnavailableView.search(text: query)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(model.allDevices.count.formatted()) chips")
            Spacer()
            Text("↑↓ move  ↩ select  esc close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Logic

    private func makeSections(_ names: [String]) -> [RowSection] {
        var sections: [RowSection] = []
        if query.isEmpty {
            // Only chips the current database has – a favourite from the
            // T48 list can't be looked up in the TL866A/CS one.
            let favorites = model.favorites.filter { model.isAvailable($0) }
            let recents = model.recents.filter { model.isAvailable($0) }.prefix(6)
            if !favorites.isEmpty {
                sections.append(RowSection(title: "Favorites",
                                           rows: favorites.map { Row(section: "Favorites", name: $0) }))
            }
            if !recents.isEmpty {
                sections.append(RowSection(title: "Recent",
                                           rows: recents.map { Row(section: "Recent", name: $0) }))
            }
        }
        let title = query.isEmpty ? "All Chips" : "Matches"
        sections.append(RowSection(title: title, rows: names.map { Row(section: title, name: $0) }))
        return sections
    }

    private func move(_ delta: Int, in sections: [RowSection]) {
        let rows = sections.flatMap(\.rows)
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == highlighted } ?? -1
        let next = min(max(current + delta, 0), rows.count - 1)
        highlighted = rows[next].id
        scrollTarget = rows[next].id
    }

    private func commit(_ sections: [RowSection]) {
        let rows = sections.flatMap(\.rows)
        if let row = rows.first(where: { $0.id == highlighted }) ?? rows.first {
            choose(row.name)
        }
    }

    private func choose(_ name: String) {
        model.selectedDevice = name
        model.chipPickerOpen = false
    }
}
