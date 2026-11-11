import AppKit
import SwiftUI

@MainActor
struct OptionsInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Socket") {
                if let adapter = model.adapter {
                    // Bank adapters fill the whole 40-pin socket.
                    ZIFDiagram(socket: model.socketLayout, package: "DIP40", mount: .board(adapter.name))
                        .padding(.vertical, 4)
                } else {
                    ZIFDiagram(socket: model.socketLayout, package: model.deviceInfo?.package,
                               mount: model.adapterPackage.map { ZIFDiagram.Mount.smd($0) } ?? .direct)
                        .padding(.vertical, 4)
                }
            }

            AdapterSection()

            Section("Memory") {
                Picker("Page", selection: $model.options.page) {
                    ForEach(MemoryPage.allCases) { page in
                        Text(page.label).tag(page)
                    }
                }
            }

            Section("Writing") {
                flag("Skip erase", "-e", $model.options.skipErase)
                flag("Skip verify", "-v", $model.options.skipVerify)
                flag("Keep write-protect on", "-u", $model.options.noProtectOff)
                flag("Don't re-enable protect", "-P", $model.options.noProtectOn)
            }

            Section {
                voltagePicker("VPP (programming)", selection: $model.options.vpp,
                              values: VoltageTable.vpp(forTL866A: model.voltagesForTL866A),
                              chipDefault: model.chipDefault("vpp"))
                voltagePicker("VDD (write)", selection: $model.options.vdd,
                              values: VoltageTable.vddVcc, chipDefault: model.chipDefault("vdd"))
                voltagePicker("VCC (verify)", selection: $model.options.vcc,
                              values: VoltageTable.vddVcc, chipDefault: model.chipDefault("vcc"))
                Picker("Pulse delay", selection: $model.options.pulse) {
                    Text(defaultLabel(model.chipDefault("pulse"))).tag(Int?.none)
                    ForEach(Self.merged(VoltageTable.pulses, model.options.pulse), id: \.self) { value in
                        Text("\(value) µs").tag(Optional(value))
                    }
                }
            } header: {
                Text("Programming voltages")
            } footer: {
                Text("Only used when writing UV EPROMs and GAL/ATF chips (minipro ignores them otherwise). VPP steps are the \(model.voltageFamilyName)'s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety checks") {
                Toggle(isOn: $model.options.pinCheckFirst) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Check pin contact first")
                            if !model.pinCheckSupported {
                                Text("TL866II+ and T48 only, not in ICSP mode")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("-z")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                flag("Skip chip ID check", "-x", $model.options.skipIDCheck)
                flag("Ignore chip ID mismatch", "-y", $model.options.ignoreIDError)
                flag("Ignore file size error", "-s", $model.options.ignoreSizeError)
                flag("Hide file size warning", "-S", $model.options.ignoreSizeWarning)
            }

            Section("In-circuit programming") {
                Picker("ICSP", selection: $model.options.icsp) {
                    ForEach(ICSPMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("Write command") {
                Text(model.previewCommand(for: .write))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if let chip = model.selectedDevice {
                    Label(model.hasChipOptions
                          ? "These options are saved for \(DeviceName.display(chip)) and come back whenever you select it."
                          : "Default options. Anything you change is remembered for \(DeviceName.display(chip)).",
                          systemImage: model.hasChipOptions ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset to Defaults") { model.options = ProgrammingOptions() }
            }
        }
        .formStyle(.grouped)
        .themedBackground(theme, theme.palette?.sidebar)
    }

    private func voltagePicker(_ title: String, selection: Binding<Double?>, values: [Double], chipDefault: String?) -> some View {
        Picker(title, selection: selection) {
            Text(defaultLabel(chipDefault)).tag(Double?.none)
            ForEach(Self.merged(values, selection.wrappedValue), id: \.self) { value in
                Text("\(VoltageTable.format(value)) V\(values.contains(value) ? "" : " – not a valid step")")
                    .tag(Optional(value))
            }
        }
    }

    private func defaultLabel(_ chipDefault: String?) -> String {
        chipDefault.map { "Chip default (\($0))" } ?? "Chip default"
    }

    /// The preset list plus a saved value that isn't in it, so the picker can show it.
    static func merged<T: Comparable & Hashable>(_ values: [T], _ current: T?) -> [T] {
        guard let current, !values.contains(current) else { return values }
        return (values + [current]).sorted()
    }

    private func flag(_ title: String, _ flag: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack {
                Text(title)
                Spacer()
                Text(flag)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @AppStorage(DefaultsKey.miniproPath) private var miniproPath = ""
    @AppStorage(DefaultsKey.pollProgrammer) private var pollProgrammer = true
    @AppStorage(DefaultsKey.completionSounds) private var completionSounds = true

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            miniproTab
                .tabItem { Label("minipro", systemImage: "memorychip") }
        }
        .frame(width: 680)
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        Form {
            Section {
                ThemePicker()
                    .padding(.vertical, 6)
            } header: {
                Label("Theme", systemImage: "paintpalette")
            } footer: {
                Text("System, Light and Dark use native macOS colours. The others recolour the whole window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .themedBackground(theme, theme.palette?.background)
        .frame(height: 520)
    }

    // MARK: minipro

    private var miniproTab: some View {
        Form {
            Section("minipro") {
                LabeledContent("In use", value: model.miniproURL?.path ?? "Not found")
                LabeledContent("Version", value: model.miniproVersion ?? "–")
                HStack {
                    TextField("Custom path", text: $miniproPath, prompt: Text("Auto-detect"))
                    Button("Choose…") { choose() }
                }
                HStack {
                    Button("Apply & Re-detect") { Task { await model.bootstrap(force: true) } }
                    if !miniproPath.isEmpty {
                        Button("Use Auto-detect") {
                            miniproPath = ""
                            Task { await model.bootstrap(force: true) }
                        }
                    }
                }
                Text("Not installed? `brew install minipro`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Watch for programmer being plugged in or out", isOn: $pollProgrammer)
                Toggle("Play a sound when long operations finish", isOn: $completionSounds)
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionString)
            }
        }
        .formStyle(.grouped)
        .themedBackground(theme, theme.palette?.background)
        .frame(height: 420)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        panel.message = "Select the minipro executable"
        if panel.runModal() == .OK, let url = panel.url {
            miniproPath = url.path
            Task { await model.bootstrap(force: true) }
        }
    }
}

// MARK: - Theme picker

@MainActor
struct ThemePicker: View {
    @AppStorage(DefaultsKey.theme) private var themeID = Theme.system.id

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(Theme.all) { theme in
                ThemeCard(theme: theme, isSelected: theme.id == themeID)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { themeID = theme.id }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(theme.name)
            }
        }
    }
}

@MainActor
struct ThemeCard: View {
    @Environment(\.theme) private var current
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            isSelected ? current.accent : Color.secondary.opacity(0.35),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(current.accent)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var preview: some View {
        if theme.appearance == .system {
            // Half light, half dark.
            HStack(spacing: 0) {
                MiniWindow(palette: Theme.light.previewPalette)
                MiniWindow(palette: Theme.dark.previewPalette)
            }
        } else {
            MiniWindow(palette: theme.previewPalette)
        }
    }
}

/// A tiny abstract window: title bar with accent dot, sidebar, content and a "hex" line.
struct MiniWindow: View {
    let palette: Theme.Palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.background
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(palette.accent).frame(width: 7, height: 7)
                    Capsule().fill(palette.secondaryText.opacity(0.55)).frame(height: 5)
                }
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(palette.sidebar)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(palette.surface)
                        HStack(spacing: 3) {
                            Capsule().fill(palette.text.opacity(0.8)).frame(width: 22, height: 3)
                            Capsule().fill(palette.success).frame(width: 10, height: 3)
                            Capsule().fill(palette.text.opacity(0.5)).frame(height: 3)
                        }
                    }
                }
            }
            .padding(9)
        }
    }
}
