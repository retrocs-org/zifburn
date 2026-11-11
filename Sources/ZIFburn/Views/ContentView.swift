import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var showInspector = true

    var body: some View {
        @Bindable var model = model

        DetailView()
            .inspector(isPresented: $showInspector) {
                OptionsInspector()
                    .inspectorColumnWidth(min: 270, ideal: 300, max: 380)
            }
            .toolbar { MainToolbar(model: model, showInspector: $showInspector) }
            .toolbarBackground(theme.palette?.sidebar ?? Color.clear, for: .windowToolbar)
            .toolbarBackground(theme.isCustom ? .visible : .automatic, for: .windowToolbar)
        .navigationTitle(model.selectedDevice.map(DeviceName.display) ?? "ZIFburn")
        .navigationSubtitle(subtitle)
        .task { await model.bootstrap() }
        .onChange(of: model.selectedDevice) { _, newValue in model.deviceSelectionChanged(newValue) }
        .onChange(of: model.options) { _, _ in model.saveOptions() }
        .onChange(of: model.database) { _, _ in model.databaseChanged() }
        .onChange(of: model.adapterID) { _, _ in model.adapterChanged() }
        .onChange(of: model.adapterSettingsKey) { _, _ in model.saveAdapterSettings() }
        .confirmationDialog(
            model.pendingConfirmation.map { model.confirmationTitle($0) } ?? "",
            isPresented: Binding(
                get: { model.pendingConfirmation != nil },
                set: { if !$0 { model.pendingConfirmation = nil } }
            ),
            presenting: model.pendingConfirmation
        ) { confirmation in
            Button(model.confirmationActionLabel(confirmation),
                   role: model.confirmationIsDestructive(confirmation) ? .destructive : nil) {
                Task { await model.confirm(confirmation) }
            }
            Button(model.confirmationCancelLabel(confirmation), role: .cancel) {
                model.confirmationCancelled(confirmation)
            }
        } message: { confirmation in
            Text(model.confirmationMessage(confirmation))
        }
        .confirmationDialog(
            "Select detected device",
            isPresented: Binding(
                get: { !model.autodetectCandidates.isEmpty },
                set: { if !$0 { model.autodetectCandidates = [] } }
            )
        ) {
            ForEach(model.autodetectCandidates.prefix(8), id: \.self) { name in
                Button(name) { model.selectDetected(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("minipro found these matches for the chip in the socket.")
        }
    }
}

@MainActor
extension ContentView {
    /// "DIP28", or "DFN8 on a DIP8 adapter" for adapter-mounted variants.
    var subtitle: String {
        guard let package = model.deviceInfo?.package else { return "" }
        if let adapter = model.adapterPackage { return "\(adapter) on a \(package) adapter" }
        return package
    }
}

struct MainToolbar: ToolbarContent {
    let model: AppModel
    @Binding var showInspector: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ProgrammerBadge(status: model.programmer) {
                Task { await model.refreshProgrammer() }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await model.readChip() } } label: {
                Label("Read", systemImage: "square.and.arrow.down")
            }
            .help("Read the chip into the buffer (⌘R)")
            .disabled(!model.canOperate)

            Menu {
                Button("Burn Buffer (Blank Check + Write + Verify)") { model.pendingConfirmation = .burnBuffer }
                    .disabled(model.buffer == nil)
                Button("Burn File…") { Task { await model.burnFile() } }
                Button("Burn ROM Set (hi/lo)…") { model.startBurnSet() }
                Divider()
                Button("Write Buffer to Chip…") { model.pendingConfirmation = .writeBuffer }
                    .disabled(model.buffer == nil)
                Button("Write File to Chip…") { model.requestWriteFile() }
            } label: {
                Label("Write", systemImage: "square.and.arrow.up")
            } primaryAction: {
                if model.buffer != nil {
                    model.pendingConfirmation = .writeBuffer
                } else {
                    model.requestWriteFile()
                }
            }
            .help("Program the chip")
            .disabled(!model.canOperate)

            Menu {
                Button("Verify Against Buffer") { Task { await model.verifyBuffer() } }
                    .disabled(model.buffer == nil)
                Button("Verify Against File…") { Task { await model.verifyFile() } }
            } label: {
                Label("Verify", systemImage: "checkmark.seal")
            } primaryAction: {
                Task {
                    if model.buffer != nil { await model.verifyBuffer() } else { await model.verifyFile() }
                }
            }
            .help("Compare chip contents")
            .disabled(!model.canOperate)

            Button { Task { await model.blankCheck() } } label: {
                Label("Blank Check", systemImage: "circle.dashed")
            }
            .help("Check whether the chip is blank (⌘B)")
            .disabled(!model.canOperate)

            Button { model.pendingConfirmation = .erase } label: {
                Label("Erase", systemImage: "eraser")
            }
            .help("Erase the chip")
            .disabled(!model.canOperate)

            Menu {
                Button("Duplicate Chip…") { model.startDuplicate() }
                    .disabled(!model.canOperate)
                Button("Batch Write Buffer…") { model.startBatch() }
                    .disabled(!model.canOperate || model.buffer == nil)
                Button("Read with Stability Check") { Task { await model.stabilityRead() } }
                    .disabled(!model.canOperate)
                Divider()
                Button("Read Chip ID") { Task { await model.readID() } }
                    .disabled(!model.canOperate)
                Button("Pin Contact Check") { Task { await model.pinCheck() } }
                    .disabled(!model.canOperate)
                Button("Logic IC Test") { Task { await model.logicTest() } }
                    .disabled(!model.canOperate)
                Divider()
                Button("Auto-detect 8-pin SPI Flash") { Task { await model.autodetect(pins: 8) } }
                Button("Auto-detect 16-pin SPI Flash") { Task { await model.autodetect(pins: 16) } }
                Divider()
                Button("Programmer Self-Test…") { model.pendingConfirmation = .selfTest }
                Button("Update Programmer Firmware…") { model.requestFirmwareUpdate() }
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }
            .disabled(!model.canUseProgrammer)

            if model.isBusy {
                Button { model.cancel() } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .help("Stop the running operation (⌘.)")
            }

            Button { showInspector.toggle() } label: {
                Label("Options", systemImage: "sidebar.trailing")
            }
            .help("Show or hide programming options")
        }
    }
}

@MainActor
struct ProgrammerBadge: View {
    @Environment(\.theme) private var theme
    let status: ProgrammerStatus
    let refresh: () -> Void

    var body: some View {
        Button(action: refresh) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(status.title)
                    .font(.callout.weight(.medium))
                if let subtitle = status.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .help(status.help)
    }

    private var color: Color {
        switch status {
        case .connected: theme.success
        case .disconnected: theme.error
        case .unknown: theme.secondaryText
        }
    }
}
