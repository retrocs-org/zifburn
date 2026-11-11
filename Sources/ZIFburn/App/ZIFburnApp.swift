import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no bundle): become a regular,
        // frontmost app with a menu bar and Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
@MainActor
struct ZIFburnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("ZIFburn", id: "main") {
            ContentView()
                .environment(model)
                .themedRoot()
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            ZIFburnCommands(model: model)
        }

        Window("ZIFburn Help", id: "help") {
            HelpView()
                .themedRoot()
                .frame(minWidth: 520, minHeight: 420)
        }
        .defaultSize(width: 680, height: 760)

        Settings {
            SettingsView()
                .environment(model)
                .themedRoot()
        }
    }
}

@MainActor
struct ZIFburnCommands: Commands {
    let model: AppModel
    @AppStorage(DefaultsKey.theme) private var themeID = Theme.system.id
    @AppStorage(DefaultsKey.hexFontSize) private var hexFontSize = 12.0
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("ZIFburn Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("minipro Project Page") {
                NSWorkspace.shared.open(URL(string: "https://gitlab.com/DavidGriffith/minipro")!)
            }
        }
        CommandGroup(after: .toolbar) {
            Menu("Theme") {
                Picker("Theme", selection: $themeID) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Button("Larger Hex Font") { hexFontSize = min(hexFontSize + 1, 18) }
                .keyboardShortcut("+")
            Button("Smaller Hex Font") { hexFontSize = max(hexFontSize - 1, 9) }
                .keyboardShortcut("-")
            Button("Default Hex Font Size") { hexFontSize = 12 }
                .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Image…") { model.openFile() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Buffer as Binary…") { model.saveBuffer(as: .binary) }
                .keyboardShortcut("s")
                .disabled(model.buffer == nil)
            Button("Save Buffer as Intel HEX…") { model.saveBuffer(as: .intelHex) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.buffer == nil)
        }

        CommandMenu("Chip") {
            Button("Select Chip…") { model.chipPickerOpen = true }
                .keyboardShortcut("l")
            Divider()
            Button("Read") { Task { await model.readChip() } }
                .keyboardShortcut("r")
                .disabled(!model.canOperate)
            Button("Write Buffer…") { model.pendingConfirmation = .writeBuffer }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.canOperate || model.buffer == nil)
            Button("Write File…") { model.requestWriteFile() }
                .disabled(!model.canOperate)
            Button("Burn Buffer") { model.pendingConfirmation = .burnBuffer }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!model.canOperate || model.buffer == nil)
            Button("Burn File…") { Task { await model.burnFile() } }
                .disabled(!model.canOperate)
            Button("Burn ROM Set (hi/lo)…") { model.startBurnSet() }
                .disabled(!model.canOperate)
            Button("Verify Against Buffer") { Task { await model.verifyBuffer() } }
                .keyboardShortcut("y")
                .disabled(!model.canOperate || model.buffer == nil)
            Button("Verify Against File…") { Task { await model.verifyFile() } }
                .disabled(!model.canOperate)
            Divider()
            Button("Duplicate Chip…") { model.startDuplicate() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!model.canOperate)
            Button("Batch Write Buffer…") { model.startBatch() }
                .disabled(!model.canOperate || model.buffer == nil)
            Button("Read with Stability Check") { Task { await model.stabilityRead() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.canOperate)
            Divider()
            Button("Blank Check") { Task { await model.blankCheck() } }
                .keyboardShortcut("b")
                .disabled(!model.canOperate)
            Button("Erase…") { model.pendingConfirmation = .erase }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!model.canOperate)
            Button("Read Chip ID") { Task { await model.readID() } }
                .keyboardShortcut("i")
                .disabled(!model.canOperate)
            Divider()
            Button("Cancel Operation") { model.cancel() }
                .keyboardShortcut(".")
                .disabled(!model.isBusy)
        }

        CommandMenu("Programmer") {
            Button("Check Connection") { Task { await model.refreshProgrammer() } }
                .keyboardShortcut("k")
                .disabled(!model.canUseProgrammer)
            Button("Reload Device List") { Task { await model.reloadDevices(force: true) } }
                .disabled(!model.canUseProgrammer)
            Divider()
            Button("Pin Contact Check") { Task { await model.pinCheck() } }
                .disabled(!model.canOperate)
            Button("Logic IC Test") { Task { await model.logicTest() } }
                .disabled(!model.canOperate)
            Button("Auto-detect 8-pin SPI Flash") { Task { await model.autodetect(pins: 8) } }
                .disabled(!model.canUseProgrammer)
            Button("Auto-detect 16-pin SPI Flash") { Task { await model.autodetect(pins: 16) } }
                .disabled(!model.canUseProgrammer)
            Divider()
            Button("Self-Test…") { model.pendingConfirmation = .selfTest }
                .disabled(!model.canUseProgrammer)
            Button("Update Firmware…") { model.requestFirmwareUpdate() }
                .disabled(!model.canUseProgrammer)
        }
    }
}
