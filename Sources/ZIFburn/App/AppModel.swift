import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum DefaultsKey {
    static let miniproPath = "miniproPath"
    static let pollProgrammer = "pollProgrammer"
    static let favorites = "favorites"
    static let recents = "recents"
    static let options = "options"
    static let database = "deviceDatabase"
    static let completionSounds = "completionSounds"
    static let theme = "theme"
    static let hexFontSize = "hexFontSize"
    static let chipOptions = "chipOptions"
    static let adapterID = "adapterID"
    static let adapterTarget = "adapterTarget"
    static let adapterOnMeansHigh = "adapterOnMeansHigh"
    static let adapterSwapBytes = "adapterSwapBytes"
    static let adapterPolarityChecked = "adapterPolarityChecked"
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
    /// Stamped into the bundle by `make app`; "dev" when run via `swift run`.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "ZIFburnBuild") as? String ?? "dev"
    }
    static var versionString: String { "ZIFburn \(version) (build \(build))" }
}

/// Which minipro chip database the chip selector shows.
enum DeviceDatabase: String, CaseIterable, Identifiable {
    case auto, tl866a, tl866ii, t76

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .tl866a: "TL866A / CS"
        case .tl866ii: "TL866II+ / T48 / T56"
        case .t76: "T76"
        }
    }

    /// minipro `-q` value; nil for Auto.
    var qFlag: String? {
        switch self {
        case .auto: nil
        case .tl866a: "tl866a"
        case .tl866ii: "t48"
        case .t76: "t76"
        }
    }
}

@Observable
@MainActor
final class AppModel {
    // MARK: minipro / programmer
    private(set) var miniproURL: URL?
    private(set) var miniproVersion: String?
    private(set) var programmer: ProgrammerStatus = .unknown

    // MARK: devices
    private(set) var allDevices: [String] = []
    private(set) var isLoadingDevices = false
    /// Drives the chip selector's dropdown (also opened from the menu, ⌘L).
    var chipPickerOpen = false
    var selectedDevice: String?
    private(set) var deviceInfo: DeviceInfo?
    /// Why chip info couldn't be loaded (shown instead of "Loading chip info…").
    private(set) var deviceInfoError: String?
    private(set) var favorites: [String]
    private(set) var recents: [String]
    var database: DeviceDatabase
    /// Databases this minipro build rejects (e.g. T76 before minipro supported it).
    private(set) var unsupportedDatabases: Set<DeviceDatabase> = []

    // MARK: options
    var options: ProgrammingOptions
    /// Options remembered per chip (only chips whose options differ from the defaults).
    private(set) var chipOptions: [String: ProgrammingOptions]

    // MARK: buffer
    private(set) var buffer: ChipBuffer?
    private(set) var bufferStats: BufferStats?
    /// Highlighted bytes in the hex view: find matches, diffs or unstable bytes.
    private(set) var marks: ByteMarks?

    // MARK: console & activity
    private(set) var log: [LogEntry] = []
    private(set) var lastCommand: String?
    private(set) var isBusy = false
    private(set) var activity: Activity?
    private(set) var lastOutcome: Outcome?
    var pendingConfirmation: PendingConfirmation?
    /// Hint (and optional fix) for the last failure.
    private(set) var suggestion: FixSuggestion?

    // MARK: adapter
    /// Selected adapter profile id ("" = none).
    var adapterID: String
    var adapterTargetID: String
    /// Whether a DIP switch in the ON position drives its address line high.
    var adapterOnMeansHigh: Bool
    /// Swap byte order of each 16-bit word when reading/burning via the adapter.
    var adapterSwapBytes: Bool
    /// Bank currently being processed (for the switch diagram).
    private(set) var adapterActiveBank: Int?
    var autodetectCandidates: [String] = []

    // MARK: internals
    @ObservationIgnored private var lowercasedDevices: [String] = []
    @ObservationIgnored private var deviceSet: Set<String> = []
    /// Which programmer database a device came from when no programmer was connected.
    @ObservationIgnored private var deviceDatabase: [String: String] = [:]
    @ObservationIgnored private var processRunning = false
    @ObservationIgnored private var current: RunningProcess?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var lastOperation: RetryableOperation?
    @ObservationIgnored private var adapterReadParts: [Data] = []
    @ObservationIgnored private var databaseAutoSwitched = false

    static let deviceListLimit = 500
    static let logLimit = 5000

    init() {
        let defaults = UserDefaults.standard
        favorites = defaults.stringArray(forKey: DefaultsKey.favorites) ?? []
        recents = defaults.stringArray(forKey: DefaultsKey.recents) ?? []
        database = DeviceDatabase(rawValue: defaults.string(forKey: DefaultsKey.database) ?? "") ?? .auto
        adapterID = defaults.string(forKey: DefaultsKey.adapterID) ?? ""
        adapterTargetID = defaults.string(forKey: DefaultsKey.adapterTarget) ?? ""
        // Earlier builds defaulted to "ON = high", the opposite of the
        // adapter's official table – reset that once to the documented value.
        if !defaults.bool(forKey: DefaultsKey.adapterPolarityChecked) {
            defaults.removeObject(forKey: DefaultsKey.adapterOnMeansHigh)
            defaults.set(true, forKey: DefaultsKey.adapterPolarityChecked)
        }
        adapterOnMeansHigh = defaults.object(forKey: DefaultsKey.adapterOnMeansHigh) as? Bool
            ?? AdapterProfile.eprom16.defaultOnMeansHigh
        adapterSwapBytes = defaults.bool(forKey: DefaultsKey.adapterSwapBytes)
        if let data = defaults.data(forKey: DefaultsKey.chipOptions),
           let saved = try? JSONDecoder().decode([String: ProgrammingOptions].self, from: data) {
            chipOptions = saved
        } else {
            chipOptions = [:]
        }
        if let data = defaults.data(forKey: DefaultsKey.options),
           let saved = try? JSONDecoder().decode(ProgrammingOptions.self, from: data) {
            options = saved
        } else {
            options = ProgrammingOptions()
        }
    }

    // MARK: - Derived state

    var canOperate: Bool { miniproURL != nil && !isBusy && selectedDevice != nil }
    var canUseProgrammer: Bool { miniproURL != nil && !isBusy }

    /// Space-separated tokens, all of which must appear in the name ("27c512 dip").
    func searchDevices(_ query: String) -> (names: [String], truncated: Bool) {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        var result: [String] = []
        for (index, lower) in lowercasedDevices.enumerated() where tokens.allSatisfy({ lower.contains($0) }) {
            if result.count >= Self.deviceListLimit { return (result, true) }
            result.append(allDevices[index])
        }
        return (result, false)
    }

    func isFavorite(_ name: String) -> Bool { favorites.contains(name) }

    /// Whether a chip (e.g. from Recent/Favorites) is in the currently loaded list.
    func isAvailable(_ name: String) -> Bool {
        _ = allDevices.count   // observation: re-evaluate when the list changes
        return deviceSet.isEmpty || deviceSet.contains(name)
    }

    /// Human name of the list that's loaded, for messages.
    var currentListName: String {
        if database != .auto { return database.label }
        return programmer.isConnected ? programmer.title : "merged"
    }

    /// The ZIF socket to draw: the connected programmer, else the chosen database.
    var socketLayout: SocketLayout {
        if let q = programmer.qFlag { return .forProgrammer(q) }
        switch database {
        case .tl866a: return .forProgrammer("tl866a")
        case .t76: return .forProgrammer("t76")
        case .auto, .tl866ii: return .forProgrammer(nil)
        }
    }

    /// minipro's "@PACKAGE" variants sometimes carry wrong settings.
    /// The chip's real package when it sits on an adapter (e.g. "DFN8").
    var adapterPackage: String? {
        ZIFburn.adapterPackage(device: selectedDevice, reportedPackage: deviceInfo?.package)
    }

    /// minipro sometimes lists a chip both plain and as "@PACKAGE" variants,
    /// whose settings can differ. Only mention it when both exist.
    var packageVariantWarning: String? {
        guard let device = selectedDevice, let at = device.firstIndex(of: "@") else { return nil }
        let base = String(device[..<at])
        guard deviceSet.contains(base) else { return nil }
        return "minipro also lists plain \(base). Package variants can carry different settings – if this one misbehaves, try \(base)."
    }

    var bufferSizeMismatch: Bool {
        guard let buffer, let expected = deviceInfo?.memoryBytes else { return false }
        return buffer.data.count != expected
    }

    func previewCommand(for op: ChipOperation) -> String {
        let device = selectedDevice ?? "<device>"
        var args = ["-p", device]
        switch op {
        case .write: args += ["-w", "image.bin"]
        case .read: args += ["-r", "image.bin"]
        case .verify: args += ["-m", "image.bin"]
        default: break
        }
        args += options.arguments(for: op)
        return Self.shellLine("minipro", Self.longOptions(args))
    }

    // MARK: - Startup

    func bootstrap(force: Bool = false) async {
        guard force || !didBootstrap else { return }
        if !didBootstrap {
            // Leftovers from a previous session.
            try? FileManager.default.removeItem(at: Self.workDirectory)
        }
        didBootstrap = true
        appendLog(.info, AppInfo.versionString)

        miniproURL = MiniproLocator.locate(override: UserDefaults.standard.string(forKey: DefaultsKey.miniproPath))
        guard let url = miniproURL else {
            miniproVersion = nil
            programmer = .disconnected("minipro not found")
            appendLog(.error, "minipro was not found. Install it with `brew install minipro`, or set its path in Settings.")
            return
        }

        if let result = await execute(["--version"], echo: false, visible: false, timeout: Self.backgroundTimeout) {
            miniproVersion = OutputParser.version(from: result.lines)
        }
        appendLog(.info, "Using minipro \(miniproVersion ?? "(unknown version)") at \(url.path)")

        // Resetting to .unknown guarantees refreshProgrammer sees a change,
        // which in turn (re)loads the device list for the right database.
        programmer = .unknown
        await refreshProgrammer()
        startPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self else { return }
                let enabled = UserDefaults.standard.object(forKey: DefaultsKey.pollProgrammer) as? Bool ?? true
                if enabled && !self.isBusy {
                    await self.refreshProgrammer(skipIfBusy: true)
                }
            }
        }
    }

    // MARK: - Programmer & device list

    func refreshProgrammer(skipIfBusy: Bool = false) async {
        guard let result = await execute(["-k"], echo: false, visible: false, skipIfBusy: skipIfBusy,
                                         timeout: Self.backgroundTimeout) else { return }
        let status = OutputParser.programmer(from: result.lines, status: result.status)
        guard status != programmer else { return }

        let previousQ = programmer.qFlag
        let wasConnected = programmer.isConnected
        programmer = status
        switch status {
        case .connected(let model, let fw, _):
            appendLog(.success, "Programmer connected: \(model)\(fw.map { ", firmware \($0)" } ?? "")")
        case .disconnected(let reason):
            appendLog(.info, "No programmer: \(reason)")
        case .unknown:
            break
        }
        // The device database depends on which programmer is attached,
        // so refresh when one appears/disappears or the model changes.
        let programmerChanged = status.isConnected != wasConnected || status.qFlag != previousQ
        if (database == .auto && programmerChanged) || allDevices.isEmpty {
            await reloadDevices()
        }
    }

    /// minipro's chip databases, one representative `-q` value each:
    /// "t48" = TL866II+/T48/T56, "tl866a" = TL866A/CS, "t76" = T76 (newer builds only;
    /// silently skipped if unsupported). Without a programmer attached, a bare
    /// `minipro -l` / `-d` stops at an interactive "Which database?" prompt,
    /// so offline calls must always pass one of these.
    static let databaseModels = ["t48", "tl866a", "t76"]
    static let backgroundTimeout: Duration = .seconds(20)

    /// Which list the cache entry represents.
    private var deviceCacheKey: String {
        if let q = database.qFlag { return q }
        if programmer.isConnected { return "auto-" + (programmer.qFlag ?? "connected") }
        return "auto-all"
    }

    /// Loads the chip list, from the on-disk cache when possible.
    /// `force` (Programmer › Reload Device List) always asks minipro.
    func reloadDevices(force: Bool = false) async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }

        var collected: [String: String?] = [:]   // device -> database it came from (nil = default)
        var lastResult: CommandResult?
        let cacheKey = deviceCacheKey
        var fromCache = false

        var source = ""
        if !force, let cached = DeviceCache.load(key: cacheKey, version: miniproVersion) {
            collected = cached.mapValues { $0.isEmpty ? nil : Optional($0) }
            fromCache = true
            if database != .auto {
                source = "for \(database.label) (cached)"
            } else if programmer.isConnected {
                source = "for \(programmer.title) (cached)"
            } else {
                source = "from all programmer databases (cached)"
            }
        } else if let q = database.qFlag {
            // A specific database was chosen in the programmer selector.
            let (names, result) = await listDevices(q: q)
            lastResult = result
            names.forEach { collected[$0] = q }
            source = "for \(database.label)"
        } else if programmer.isConnected {
            // Auto: minipro picks the attached programmer's database itself.
            let (names, result) = await listDevices(q: nil)
            lastResult = result
            names.forEach { collected[$0] = .some(nil) }
            source = "for \(programmer.title)"
        }

        // Auto with no programmer (or nothing listed): merge every database
        // explicitly so chips can be browsed offline without minipro's prompt.
        if !fromCache && collected.isEmpty && database == .auto {
            for q in Self.databaseModels {
                let (names, result) = await listDevices(q: q)
                if result != nil { lastResult = result }
                for name in names where collected[name] == nil { collected[name] = q }
            }
            source = "from all programmer databases (no programmer connected)"
        }

        if collected.isEmpty, database != .auto, unsupportedDatabases.contains(database) {
            appendLog(.error, "minipro \(miniproVersion ?? "") doesn't know the \(database.label) database. Update it with `brew upgrade minipro`, or choose another programmer. Switching back to Auto.")
            lastOutcome = Outcome(success: false, message: "\(database.label) needs a newer minipro")
            databaseAutoSwitched = true
            database = .auto   // ContentView's onChange reloads the list
            return
        }

        // Ordinary part numbers first; minipro's "(VENDOR)…" / "(2xFF)…" bundle
        // entries go last so the unfiltered list starts with familiar chips.
        let display = Dictionary(uniqueKeysWithValues: collected.keys.map { ($0, DeviceName.display($0)) })
        let names = collected.keys.sorted { a, b in
            let da = display[a] ?? a, db = display[b] ?? b
            let aBundle = da.hasPrefix("("), bBundle = db.hasPrefix("(")
            if aBundle != bBundle { return !aBundle }
            return da.localizedStandardCompare(db) == .orderedAscending
        }
        allDevices = names
        lowercasedDevices = names.map { (display[$0] ?? $0).lowercased() }
        if !fromCache {
            DeviceCache.save(collected.mapValues { $0 ?? "" }, key: cacheKey, version: miniproVersion)
        }
        deviceSet = Set(names)
        deviceDatabase = collected.compactMapValues { $0 }

        if names.isEmpty {
            let reason = lastResult.map { $0.failureReason } ?? "no output"
            appendLog(.error, "minipro returned no devices (\(reason)). Try `minipro -l` in a terminal.")
        } else {
            appendLog(.info, "Loaded \(names.count.formatted()) devices\(source.isEmpty ? "" : " " + source).")
            if let selected = selectedDevice, !deviceSet.contains(selected) {
                appendLog(.info, "\(DeviceName.display(selected)) isn't in the \(currentListName) database – choose a chip again.")
                selectedDevice = nil
            }
        }
    }

    private func listDevices(q: String?) async -> (names: [String], result: CommandResult?) {
        var args = ["-l"]
        if let q { args += ["-q", q] }
        guard let result = await execute(args, echo: false, visible: false, timeout: Self.backgroundTimeout) else { return ([], nil) }
        // Device names normally arrive on stdout; tolerate builds that print them on stderr.
        let lines = result.stdout.count >= 20 ? result.stdout
            : (result.stderr.count >= 20 ? result.stderr : result.stdout)
        let names = OutputParser.deviceList(from: lines)
        // An unknown -q value makes minipro print its usage text and list nothing.
        if let q, names.isEmpty, let db = DeviceDatabase.allCases.first(where: { $0.qFlag == q }) {
            unsupportedDatabases.insert(db)
        }
        return (names, result)
    }

    func databaseChanged() {
        UserDefaults.standard.set(database.rawValue, forKey: DefaultsKey.database)
        // A message from an automatic fallback stays visible; anything older
        // is stale once the user picks another database.
        if databaseAutoSwitched {
            databaseAutoSwitched = false
        } else if lastOutcome?.success == false {
            lastOutcome = nil
        }
        Task {
            await reloadDevices()
            // The chip may still be selected, but its info came from the old
            // database ("Available on", sizes…) – fetch it again.
            if let name = selectedDevice {
                deviceInfo = nil
                deviceInfoError = nil
                await loadInfo(for: name)
            }
        }
    }

    func deviceSelectionChanged(_ name: String?) {
        deviceInfo = nil
        deviceInfoError = nil
        guard let name else { return }
        recents.removeAll { $0 == name }
        recents.insert(name, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        UserDefaults.standard.set(recents, forKey: DefaultsKey.recents)

        // Each chip keeps its own options (e.g. --no_id_error for a clone EPROM);
        // chips without saved options start from the defaults.
        let restored = chipOptions[name] ?? ProgrammingOptions()
        if restored != options {
            options = restored
            if chipOptions[name] != nil {
                appendLog(.info, "Restored saved options for \(DeviceName.display(name)).")
            }
        }
        suggestion = nil
        Task { await loadInfo(for: name) }
    }

    private func loadInfo(for name: String) async {
        var args = ["-d", name]
        if let q = database.qFlag {
            args += ["-q", q]
        } else if !programmer.isConnected, let q = deviceDatabase[name] ?? Self.databaseModels.first {
            args += ["-q", q]
        }
        guard let result = await execute(args, echo: false, visible: false, timeout: Self.backgroundTimeout) else { return }
        guard selectedDevice == name else { return } // user moved on meanwhile
        deviceInfo = OutputParser.deviceInfo(from: result.lines, fallbackName: name)
        if deviceInfo == nil {
            let display = DeviceName.display(name)
            let notFound = result.lines.joined(separator: " ").lowercased().contains("not found")
            deviceInfoError = notFound
                ? "\(display) isn't in the \(currentListName) database. Pick another programmer above, or another chip."
                : "No chip info: \(result.failureReason)"
            appendLog(.error, "Could not get info for \(display): \(result.failureReason)")
        }
    }

    func toggleFavorite(_ name: String) {
        if let i = favorites.firstIndex(of: name) {
            favorites.remove(at: i)
        } else {
            favorites.append(name)
            favorites.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        UserDefaults.standard.set(favorites, forKey: DefaultsKey.favorites)
    }

    func saveOptions() {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.options)
        }
        guard let device = selectedDevice else { return }
        let stored = options == ProgrammingOptions() ? nil : options
        guard chipOptions[device] != stored else { return }
        chipOptions[device] = stored
        persistChipOptions()
    }

    /// Which programmer's VPP steps apply.
    var voltagesForTL866A: Bool {
        if let q = programmer.qFlag { return q == "tl866a" }
        return database == .tl866a
    }

    var voltageFamilyName: String { voltagesForTL866A ? "TL866A/CS" : "TL866II+" }

    /// The chip's own setting as reported by `minipro -d` (e.g. "12.5V"), if listed.
    func chipDefault(_ keyword: String) -> String? {
        deviceInfo?.fields.first { $0.key.lowercased().contains(keyword) }?.value
    }

    /// Saves the adapter guide's pulse/VPP for the adapter's stand-in device.
    func applyAdapterGuideSettings() {
        guard let adapter else { return }
        var target = selectedDevice == adapter.device ? options : (chipOptions[adapter.device] ?? ProgrammingOptions())
        if let pulse = adapter.guidePulse { target.pulse = pulse }
        if let vpp = adapter.guideVPP { target.vpp = vpp }
        if selectedDevice == adapter.device {
            options = target
        } else {
            chipOptions[adapter.device] = target
            persistChipOptions()
        }
        let parts = [adapter.guidePulse.map { "pulse \($0) µs" }, adapter.guideVPP.map { "VPP \(VoltageTable.format($0)) V" }]
            .compactMap { $0 }.joined(separator: ", ")
        succeed("Saved the adapter guide's settings for \(DeviceName.display(adapter.device)): \(parts)")
    }

    private func persistChipOptions() {
        if let data = try? JSONEncoder().encode(chipOptions) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.chipOptions)
        }
    }

    /// True when the selected chip has its own saved options.
    var hasChipOptions: Bool {
        selectedDevice.map { chipOptions[$0] != nil } ?? false
    }

    // MARK: - Chip operations

    /// Flags for an operation. During adapter jobs the chip ID check is
    /// always skipped (-x), as the adapter's guide says: the stand-in device's
    /// ID never matches the real chip.
    private func chipArgs(_ op: ChipOperation) -> [String] {
        var args = options.arguments(for: op)
        if adapterActiveBank != nil, op != .pinCheck, op != .logicTest {
            args.removeAll { $0 == "-y" }
            if !args.contains("-x") { args.append("-x") }
        }
        return args
    }

    // MARK: Pin-contact preflight

    /// minipro's pin check exists on the TL866II+ and T48 only, and not in ICSP mode.
    var pinCheckSupported: Bool {
        guard let q = programmer.qFlag, options.icsp == .off else { return false }
        return q == "t48" || q == "tl866ii"
    }

    /// Runs `-z` before an operation when enabled. Returns false to abort.
    private func preflight(_ device: String) async -> Bool {
        // Pin detection doesn't work through adapter boards ("uncheck Pin Detect").
        guard options.pinCheckFirst, pinCheckSupported, adapterActiveBank == nil else { return true }
        guard let result = await execute(["-p", device, "-z"], title: "Checking pin contact") else { return false }
        if result.succeeded { return true }
        fail("Bad pin contact – reseat the chip, close the lever and try again", result, sound: true)
        return false
    }

    // MARK: Read

    @discardableResult
    func readChip() async -> Bool {
        guard let device = requireDevice() else { return false }
        guard confirmDiscardEdits() else { return false }
        lastOperation = .read
        guard await preflight(device) else { return false }
        guard let image = await readImage(device: device, title: "Reading \(device)") else { return false }
        setBuffer(ChipBuffer(data: image.data, origin: .chip(device: device, date: Date()), extraFiles: image.extras))
        if !image.extras.isEmpty {
            appendLog(.info, "minipro also wrote: \(image.extras.map(\.lastPathComponent).joined(separator: ", "))")
        }
        succeed("Read \(Self.size(image.data.count)) from \(device)", sound: true)
        return true
    }

    private func readImage(device: String, title: String) async -> (data: Data, extras: [URL])? {
        let dir = Self.workDirectory.appendingPathComponent("read-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(Sanitize.fileName(device)).bin")

        let args = ["-p", device, "-r", file.path] + chipArgs(.read)
        guard let result = await execute(args, title: title) else { return nil }
        guard result.succeeded, let data = try? Data(contentsOf: file) else {
            fail("Read failed", result, sound: true)
            return nil
        }
        let extras = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != file.lastPathComponent }
        return (data, extras)
    }

    /// Reads the chip several times and compares the passes. Marginal or
    /// ageing EPROMs often return a few flipping bits; the buffer gets the
    /// per-byte majority vote and the unstable bytes are highlighted.
    func stabilityRead(passes: Int = 3) async {
        guard let device = requireDevice() else { return }
        guard confirmDiscardEdits() else { return }
        guard await preflight(device) else { return }
        var images: [Data] = []
        var extras: [URL] = []
        for pass in 1...passes {
            guard let image = await readImage(device: device, title: "Stability check – read \(pass) of \(passes)") else { return }
            images.append(image.data)
            if pass == 1 { extras = image.extras }
        }
        guard Set(images.map(\.count)).count == 1 else {
            fail("Stability check: the reads returned different sizes (\(images.map { Self.size($0.count) }.joined(separator: ", ")))")
            return
        }
        let analysis = await Task.detached(priority: .userInitiated) { StabilityAnalysis(images) }.value
        setBuffer(ChipBuffer(data: analysis.consensus, origin: .chip(device: device, date: Date()), extraFiles: extras))
        if analysis.unstable.isEmpty {
            succeed("Stable: \(passes) reads of \(device) are identical", sound: true)
        } else {
            let count = analysis.unstable.count
            marks = ByteMarks(kind: .unstable, title: "\(count.formatted()) unstable bytes",
                              indexes: analysis.unstable,
                              anchors: analysis.unstable.rangeView.prefix(10_000).map(\.lowerBound))
            fail("Unstable: \(count.formatted()) bytes changed between reads. The buffer holds the majority vote – the chip may be failing or badly seated.", sound: true)
        }
    }

    // MARK: Write

    @discardableResult
    func writeBuffer() async -> Bool {
        guard let device = requireDevice() else { return false }
        lastOperation = .writeBuffer
        guard let buffer else {
            fail("Nothing in the buffer to write")
            return false
        }
        guard let file = writeTemp(buffer.data, name: "write.bin") else { return false }
        return await write(file: file, device: device, label: buffer.title)
    }

    @discardableResult
    func writeFile(_ url: URL) async -> Bool {
        guard let device = requireDevice() else { return false }
        lastOperation = .writeFile(url)
        return await write(file: url, device: device, label: url.lastPathComponent)
    }

    private func write(file: URL, device: String, label: String, checkContact: Bool = true) async -> Bool {
        if checkContact {
            guard await preflight(device) else { return false }
        }
        let args = ["-p", device, "-w", file.path] + chipArgs(.write)
        let stages = 1 + (options.skipVerify ? 0 : 1)   // + erase, detected from minipro's output
        guard let result = await execute(args, title: "Writing \(label) → \(device)", stages: stages) else { return false }
        if result.succeeded {
            succeed("Wrote \(label) to \(device)\(options.skipVerify ? " (not verified)" : " and verified")", sound: true)
            return true
        }
        fail("Write failed", result, sound: true)
        return false
    }

    // MARK: Burn (blank check → write → verify)

    enum BurnSource {
        case buffer
        case file(URL)
    }

    /// The classic EPROM sequence in one step: blank check, then write, which
    /// minipro verifies automatically unless "Skip verify" is on.
    @discardableResult
    func burn(_ source: BurnSource) async -> Bool {
        guard let device = requireDevice() else { return false }
        switch source {
        case .buffer: lastOperation = .burnBuffer
        case .file(let url): lastOperation = .burnFile(url)
        }
        let file: URL
        let label: String
        switch source {
        case .buffer:
            guard let buffer, let temp = writeTemp(buffer.data, name: "burn.bin") else {
                fail("Nothing in the buffer to burn")
                return false
            }
            file = temp
            label = buffer.title
        case .file(let url):
            file = url
            label = url.lastPathComponent
        }

        guard await preflight(device) else { return false }
        let blankArgs = ["-p", device, "-b"] + chipArgs(.blankCheck)
        guard let blank = await execute(blankArgs, title: "Blank-checking \(device)") else { return false }
        guard blank.succeeded else {
            fail("\(device) isn't blank – UV-erase it (EPROM) or use Erase/Write (EEPROM, flash)", blank, sound: true)
            return false
        }
        return await write(file: file, device: device, label: label, checkContact: false)
    }

    func burnFile() async {
        guard canOperate, let url = chooseFile(title: "Choose an image to burn") else { return }
        pendingConfirmation = .burnFile(url)
    }

    /// Burn several images to several chips in turn, e.g. the -hi and -lo
    /// halves of a 32-bit Amiga Kickstart, prompting for each chip.
    func startBurnSet() {
        guard canOperate else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the images to burn, one per chip"
        panel.message = "Select all images of the set, e.g. the -hi and -lo halves of a Kickstart ROM."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let files = panel.urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        pendingConfirmation = .burnSetNext(files: files, index: 0, lastFailed: false)
    }

    private func burnSetStep(files: [URL], index: Int) async {
        if await burn(.file(files[index])) {
            if index + 1 < files.count {
                pendingConfirmation = .burnSetNext(files: files, index: index + 1, lastFailed: false)
            } else {
                succeed("All \(files.count) chips burned\(options.skipVerify ? " (not verified)" : " and verified")", sound: true)
            }
        } else {
            pendingConfirmation = .burnSetNext(files: files, index: index, lastFailed: true)
        }
    }

    // MARK: Adapter (bank-switched chips)

    var adapter: AdapterProfile? { AdapterProfile.all.first { $0.id == adapterID } }

    var adapterTarget: AdapterProfile.Target? {
        guard let adapter else { return nil }
        return adapter.targets.first { $0.id == adapterTargetID } ?? adapter.targets.first
    }

    /// Changes whenever an adapter setting changes (persisted by ContentView).
    var adapterSettingsKey: String {
        "\(adapterID)|\(adapterTargetID)|\(adapterOnMeansHigh)|\(adapterSwapBytes)"
    }

    /// Call when the adapter selection changes: adopt its documented polarity.
    func adapterChanged() {
        if let adapter { adapterOnMeansHigh = adapter.defaultOnMeansHigh }
    }

    func saveAdapterSettings() {
        let d = UserDefaults.standard
        d.set(adapterID, forKey: DefaultsKey.adapterID)
        d.set(adapterTargetID, forKey: DefaultsKey.adapterTarget)
        d.set(adapterOnMeansHigh, forKey: DefaultsKey.adapterOnMeansHigh)
        d.set(adapterSwapBytes, forKey: DefaultsKey.adapterSwapBytes)
    }

    /// Starts a bank-by-bank job. Burn and verify use the buffer as the image.
    func startAdapterJob(_ kind: AdapterJob.Kind) {
        guard canUseProgrammer, let adapter, let target = adapterTarget else { return }

        // Every bank is programmed as the adapter's stand-in device.
        if selectedDevice != adapter.device {
            if !deviceSet.isEmpty, !deviceSet.contains(adapter.device) {
                fail("\(adapter.device) isn't in the \(currentListName) database – set the programmer box to Auto or TL866II+ / T48 / T56")
                return
            }
            selectedDevice = adapter.device
        }

        var files: [URL] = []
        if kind == .burn || kind == .verify {
            guard let buffer else { return fail("Read or open the \(target.id) image into the buffer first") }
            var data = buffer.data
            if adapterSwapBytes { data = Self.swapBytes16(data) }
            let size = adapter.size(of: target)
            guard data.count <= size else {
                return fail("The image is \(Self.size(data.count)), but a \(target.id) holds \(Self.size(size))")
            }
            if data.count < size {
                appendLog(.info, "Image is \(Self.size(data.count)); padding with $FF to \(Self.size(size)) for the \(target.id).")
                data.append(contentsOf: repeatElement(UInt8(0xFF), count: size - data.count))
            }
            for bank in 0..<target.banks {
                let slice = data.subdata(in: (bank * adapter.bankSize)..<((bank + 1) * adapter.bankSize))
                guard let url = writeTemp(slice, name: "\(target.id)-bank\(bank + 1).bin") else { return }
                files.append(url)
            }
        } else if kind == .read {
            guard confirmDiscardEdits() else { return }
        }

        adapterReadParts = []
        let job = AdapterJob(kind: kind, targetID: target.id, banks: target.banks, bankFiles: files)
        pendingConfirmation = .adapterBank(job: job, bank: 0, lastFailed: false)
    }

    private func adapterStep(_ job: AdapterJob, bank: Int) async {
        guard let device = requireDevice() else { return }
        adapterActiveBank = bank
        let ok: Bool
        switch job.kind {
        case .read:
            if await preflight(device),
               let image = await readImage(device: device, title: "Reading \(job.targetID) bank \(bank + 1) of \(job.banks)") {
                if adapterReadParts.count > bank {
                    adapterReadParts[bank] = image.data
                } else {
                    adapterReadParts.append(image.data)
                }
                ok = true
            } else {
                ok = false
            }
        case .burn:
            ok = await burn(.file(job.bankFiles[bank]))
        case .verify:
            ok = await verify(file: job.bankFiles[bank], device: device, label: "bank \(bank + 1)")
        case .blankCheck:
            let args = ["-p", device, "-b"] + chipArgs(.blankCheck)
            if await preflight(device),
               let result = await execute(args, title: "Blank-checking \(job.targetID) bank \(bank + 1) of \(job.banks)") {
                ok = result.succeeded
                if !ok { fail("Bank \(bank + 1) of the \(job.targetID) isn't blank", result) }
            } else {
                ok = false
            }
        }

        if !ok {
            if suggestion?.action == nil, let tips = adapter?.troubleshooting {
                suggestion = FixSuggestion(hint: tips)
            }
            pendingConfirmation = .adapterBank(job: job, bank: bank, lastFailed: true)
        } else if bank + 1 < job.banks {
            pendingConfirmation = .adapterBank(job: job, bank: bank + 1, lastFailed: false)
        } else {
            finishAdapterJob(job)
        }
    }

    private func finishAdapterJob(_ job: AdapterJob) {
        adapterActiveBank = nil
        switch job.kind {
        case .read:
            var data = Data()
            adapterReadParts.forEach { data.append($0) }
            if adapterSwapBytes { data = Self.swapBytes16(data) }
            setBuffer(ChipBuffer(data: data, origin: .chip(device: "\(job.targetID) via adapter", date: Date())))
            succeed("Read the \(job.targetID): \(job.banks) bank\(job.banks == 1 ? "" : "s"), \(Self.size(data.count))", sound: true)
        case .burn:
            succeed("\(job.targetID) burned\(options.skipVerify ? " (not verified)" : " and verified") – all \(job.banks) bank\(job.banks == 1 ? "" : "s"). Cover the UV window with a label.", sound: true)
        case .verify:
            succeed("\(job.targetID) matches the buffer in all \(job.banks) bank\(job.banks == 1 ? "" : "s")", sound: true)
        case .blankCheck:
            succeed("\(job.targetID) is blank in all \(job.banks) bank\(job.banks == 1 ? "" : "s")")
        }
        adapterReadParts = []
    }

    /// Swaps the two bytes of every 16-bit word (a trailing odd byte is kept).
    static func swapBytes16(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            bytes.swapAt(i, i + 1)
            i += 2
        }
        return Data(bytes)
    }

    func swapBufferBytes() {
        guard let buffer else { return }
        replaceBufferData(Self.swapBytes16(buffer.data), note: "Swapped the byte order of every 16-bit word")
    }

    // MARK: Duplicate & batch

    /// Xgpro-style copy: read a master chip, then write it to blank chips.
    func startDuplicate() {
        guard canOperate else { return }
        pendingConfirmation = .duplicateMaster
    }

    /// Write the current buffer to a series of chips, with a pass/fail count.
    func startBatch() {
        guard canOperate else { return }
        guard buffer != nil else { return fail("Load or read an image into the buffer first") }
        pendingConfirmation = .batchNext(done: 0, failed: 0, lastFailed: false)
    }

    private func batchWrite(done: Int, failed: Int) async {
        let ok = await writeBuffer()
        pendingConfirmation = .batchNext(done: done + (ok ? 1 : 0), failed: failed + (ok ? 0 : 1), lastFailed: !ok)
    }

    // MARK: Verify & checks

    func verifyBuffer() async {
        guard let device = requireDevice() else { return }
        lastOperation = .verifyBuffer
        guard let buffer else { return fail("Nothing in the buffer to verify against") }
        guard let file = writeTemp(buffer.data, name: "verify.bin") else { return }
        await verify(file: file, device: device, label: buffer.title)
    }

    func verifyFile(_ preset: URL? = nil) async {
        guard let device = requireDevice() else { return }
        guard let url = preset ?? chooseFile(title: "Verify chip against file") else { return }
        lastOperation = .verifyFile(url)
        await verify(file: url, device: device, label: url.lastPathComponent)
    }

    @discardableResult
    private func verify(file: URL, device: String, label: String) async -> Bool {
        guard await preflight(device) else { return false }
        let args = ["-p", device, "-m", file.path] + chipArgs(.verify)
        guard let result = await execute(args, title: "Verifying \(device) against \(label)") else { return false }
        if result.succeeded {
            succeed("\(device) matches \(label)", sound: true)
            return true
        }
        fail("Verify failed", result, sound: true)
        return false
    }

    func blankCheck() async {
        guard let device = requireDevice() else { return }
        lastOperation = .blankCheck
        guard await preflight(device) else { return }
        let args = ["-p", device, "-b"] + chipArgs(.blankCheck)
        guard let result = await execute(args, title: "Blank-checking \(device)") else { return }
        result.succeeded ? succeed("\(device) is blank") : fail("\(device) is not blank", result)
    }

    func erase() async {
        guard let device = requireDevice() else { return }
        lastOperation = .erase
        guard await preflight(device) else { return }
        let args = ["-p", device, "-E"] + chipArgs(.erase)
        guard let result = await execute(args, title: "Erasing \(device)") else { return }
        result.succeeded ? succeed("Erased \(device)", sound: true) : fail("Erase failed", result, sound: true)
    }

    func readID() async {
        guard let device = requireDevice() else { return }
        lastOperation = .readID
        guard await preflight(device) else { return }
        let args = ["-p", device, "-D"] + chipArgs(.readID)
        guard let result = await execute(args, title: "Reading chip ID") else { return }
        let idLine = result.lines.last { $0.lowercased().contains("id") } ?? result.lines.last ?? ""
        result.succeeded ? succeed(idLine) : fail("Could not read ID", result)
    }

    func pinCheck() async {
        guard let device = requireDevice() else { return }
        guard let result = await execute(["-p", device, "-z"], title: "Checking pin contact") else { return }
        result.succeeded ? succeed("All pins make good contact") : fail("Pin check failed", result)
    }

    func logicTest() async {
        guard let device = requireDevice() else { return }
        guard let result = await execute(["-p", device, "-T"], title: "Testing logic IC \(device)") else { return }
        result.succeeded ? succeed("\(device) passed the logic test") : fail("Logic test failed", result)
    }

    func autodetect(pins: Int) async {
        guard canUseProgrammer else { return }
        guard let result = await execute(["-a", String(pins)], title: "Auto-detecting \(pins)-pin SPI flash") else { return }
        var found: [String] = []
        for line in result.lines {
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }) {
                let name = String(token)
                if deviceSet.contains(name) && !found.contains(name) { found.append(name) }
            }
        }
        if found.isEmpty {
            fail("No matching SPI device detected", result)
        } else {
            succeed("Detected \(found.count) candidate\(found.count == 1 ? "" : "s")")
            autodetectCandidates = found
        }
    }

    func selectDetected(_ name: String) {
        selectedDevice = name
        autodetectCandidates = []
    }

    func selfTest() async {
        guard canUseProgrammer else { return }
        guard let result = await execute(["-t"], title: "Programmer self-test") else { return }
        result.succeeded ? succeed("Programmer self-test passed") : fail("Self-test failed", result)
    }

    func updateFirmware(_ url: URL) async {
        guard canUseProgrammer else { return }
        guard let result = await execute(["-F", url.path], title: "Updating programmer firmware") else { return }
        if result.succeeded {
            succeed("Firmware updated – reconnect the programmer", sound: true)
            programmer = .unknown
            await refreshProgrammer()
        } else {
            fail("Firmware update failed", result, sound: true)
        }
    }

    func cancel() {
        guard let current, isBusy else { return }
        appendLog(.info, "Cancelling…")
        current.interrupt()
    }

    // MARK: - Confirmations

    func requestWriteFile() {
        guard let url = chooseFile(title: "Choose an image to write (.bin, .hex, .srec)") else { return }
        pendingConfirmation = .writeFile(url)
    }

    func requestFirmwareUpdate() {
        guard let url = chooseFile(title: "Choose a programmer firmware file") else { return }
        pendingConfirmation = .firmware(url)
    }

    func confirm(_ confirmation: PendingConfirmation) async {
        switch confirmation {
        case .burnBuffer: await burn(.buffer)
        case .burnFile(let url): await burn(.file(url))
        case .writeBuffer: await writeBuffer()
        case .writeFile(let url): await writeFile(url)
        case .erase: await erase()
        case .firmware(let url): await updateFirmware(url)
        case .selfTest: await selfTest()
        case .duplicateMaster:
            if await readChip() {
                pendingConfirmation = .batchNext(done: 0, failed: 0, lastFailed: false)
            }
        case .batchNext(let done, let failed, _):
            await batchWrite(done: done, failed: failed)
        case .burnSetNext(let files, let index, _):
            await burnSetStep(files: files, index: index)
        case .adapterBank(let job, let bank, _):
            await adapterStep(job, bank: bank)
        }
    }

    func confirmationCancelled(_ c: PendingConfirmation) {
        if case .adapterBank(let job, let bank, _) = c {
            adapterActiveBank = nil
            adapterReadParts = []
            if bank > 0 { fail("\(job.targetID) stopped after \(bank) of \(job.banks) banks") }
        }
        if case .burnSetNext(let files, let index, _) = c, index > 0 {
            fail("Set stopped after \(index) of \(files.count) chips")
        }
        if case .batchNext(let done, let failed, _) = c, done + failed > 0 {
            let summary = "Batch finished: \(done) written\(failed > 0 ? ", \(failed) failed" : "")"
            failed == 0 ? succeed(summary) : fail(summary)
        }
    }

    func confirmationTitle(_ c: PendingConfirmation) -> String {
        let device = selectedDevice ?? "chip"
        switch c {
        case .burnBuffer, .burnFile: return "Burn \(device)?"
        case .writeBuffer, .writeFile: return "Program \(device)?"
        case .erase: return "Erase \(device)?"
        case .firmware: return "Update programmer firmware?"
        case .selfTest: return "Run programmer self-test?"
        case .duplicateMaster: return "Duplicate a chip"
        case .batchNext(let done, let failed, _):
            if done + failed == 0 { return "Insert a blank chip" }
            return "Batch: \(done) written\(failed > 0 ? ", \(failed) failed" : "")"
        case .burnSetNext(let files, let index, _):
            return "Chip \(index + 1) of \(files.count): \(files[index].lastPathComponent)"
        case .adapterBank(let job, let bank, _):
            return job.banks == 1
                ? "\(job.targetID) via adapter"
                : "\(job.targetID) – \(AdapterProfile.partName(bank)) of \(String(format: "%03d", job.banks))"
        }
    }

    func confirmationMessage(_ c: PendingConfirmation) -> String {
        switch c {
        case .burnBuffer, .burnFile:
            let image: String
            if case .burnFile(let url) = c { image = url.lastPathComponent } else { image = "The buffer (\(Self.size(buffer?.data.count ?? 0)))" }
            return "\(image) will be written after a blank check. \(options.skipVerify ? "Verification is disabled; the result will not be verified." : "The written image will be verified.") Confirm the selected chip and orientation before continuing."
        case .writeBuffer:
            var msg = "The buffer (\(Self.size(buffer?.data.count ?? 0))) will be written to the chip."
            if let expected = deviceInfo?.memoryBytes, bufferSizeMismatch {
                msg += "\n\nThe chip holds \(Self.size(expected)) – sizes don't match."
                if !options.ignoreSizeError { msg += " minipro will refuse unless “Ignore file size error” is on." }
            }
            if options.skipErase { msg += "\n\nErase is skipped." }
            return msg
        case .writeFile(let url):
            return "\(url.lastPathComponent) will be written to the chip. minipro detects Intel HEX and S-record files automatically."
        case .erase:
            return "Everything on the chip will be lost."
        case .firmware(let url):
            return "\(url.lastPathComponent) will be flashed to the programmer. Do not unplug it until the update has finished."
        case .selfTest:
            return "Remove any chip from the socket before starting."
        case .duplicateMaster:
            return "Put the chip you want to copy (the master) in the socket and close the lever. ZIFburn reads it into the buffer, then asks for blank chips to write copies to."
        case .batchNext(let done, let failed, let lastFailed):
            if lastFailed {
                return "That chip failed (\(failed) so far). Reseat or replace it and retry, or stop."
            }
            if done == 0 {
                return "Put a blank or erased chip in the socket and close the lever. The buffer (\(Self.size(buffer?.data.count ?? 0))) will be written\(options.skipVerify ? "" : " and verified")."
            }
            return "Chip \(done) is done. Insert the next blank chip, or stop."
        case .burnSetNext(let files, let index, let lastFailed):
            let name = files[index].lastPathComponent
            if lastFailed {
                return "Burning \(name) failed. Reseat, UV-erase or replace the chip and retry, or stop."
            }
            let next = index + 1 < files.count ? " Then you'll be asked for the chip for \(files[index + 1].lastPathComponent)." : ""
            return "Insert a blank chip for \(name) and close the lever – label it now so the halves don't get mixed up. ZIFburn blank-checks and writes it. \(options.skipVerify ? "Verification is disabled." : "The written image will be verified.")\(next)"
        case .adapterBank(let job, let bank, let lastFailed):
            if lastFailed {
                return "\(AdapterProfile.partName(bank)) failed. \(adapter?.troubleshooting ?? "Check the switches and the chip seating.") Then retry, or stop."
            }
            guard let adapter, let target = adapter.targets.first(where: { $0.id == job.targetID }) else { return "" }
            let setting = adapter.describe(bank: bank, target: target, onMeansHigh: adapterOnMeansHigh)
            var msg = "\(AdapterProfile.partName(bank)): \(setting)."
            if bank == 0 {
                msg = adapter.insertion + "\n\n" + msg
                if job.kind == .burn { msg += " The chip must be blank (UV-erased)." }
            }
            return msg
        }
    }

    func confirmationActionLabel(_ c: PendingConfirmation) -> String {
        switch c {
        case .burnBuffer, .burnFile: "Burn"
        case .writeBuffer, .writeFile: "Write"
        case .erase: "Erase"
        case .firmware: "Update Firmware"
        case .selfTest: "Run Self-Test"
        case .duplicateMaster: "Read Master"
        case .batchNext(let done, _, let lastFailed): lastFailed ? "Retry" : (done == 0 ? "Write" : "Write Next")
        case .burnSetNext(_, _, let lastFailed): lastFailed ? "Retry" : "Burn"
        case .adapterBank(let job, _, let lastFailed): lastFailed ? "Retry" : Self.adapterActionLabel(job)
        }
    }

    private static func adapterActionLabel(_ job: AdapterJob) -> String {
        let single = job.banks == 1
        switch job.kind {
        case .read: return single ? "Read" : "Read Bank"
        case .burn: return single ? "Burn" : "Burn Bank"
        case .verify: return single ? "Verify" : "Verify Bank"
        case .blankCheck: return single ? "Blank Check" : "Check Bank"
        }
    }

    func confirmationCancelLabel(_ c: PendingConfirmation) -> String {
        if case .batchNext = c { return "Stop" }
        if case .burnSetNext = c { return "Stop" }
        if case .adapterBank = c { return "Stop" }
        return "Cancel"
    }

    func confirmationIsDestructive(_ c: PendingConfirmation) -> Bool {
        switch c {
        case .writeBuffer, .writeFile, .burnBuffer, .burnFile, .erase, .firmware: true
        case .selfTest, .duplicateMaster, .batchNext, .burnSetNext, .adapterBank: false
        }
    }

    // MARK: - Buffer & files

    func openFile() {
        guard let url = chooseFile(title: "Open image into buffer") else { return }
        loadFile(url)
    }

    enum ImageImportError: LocalizedError {
        case sRecord
        var errorDescription: String? { "S-record buffer import is not supported. Use Write File or Verify Against File for S-record images, or convert the image to binary or Intel HEX first." }
    }

    static func loadImageData(_ url: URL) throws -> Data {
        if ["srec", "srecord", "s19", "s28", "s37", "s1", "s2", "s3", "mot", "s", "sx"].contains(url.pathExtension.lowercased()) {
            throw ImageImportError.sRecord
        }
        if ["hex", "ihx", "ihex", "mcs"].contains(url.pathExtension.lowercased()) {
            return try IntelHex.decode(String(contentsOf: url, encoding: .ascii))
        }
        let data = try Data(contentsOf: url)
        let prefix = String(decoding: data.prefix(256), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.first == "S", let type = prefix.dropFirst().first, type.isNumber { throw ImageImportError.sRecord }
        return data
    }

    func loadFile(_ url: URL) {
        guard confirmDiscardEdits() else { return }
        do {
            let data = try Self.loadImageData(url)
            setBuffer(ChipBuffer(data: data, origin: .file(url)))
            appendLog(.info, "Loaded \(url.lastPathComponent) (\(Self.size(data.count))) into the buffer.")
        } catch {
            fail("Could not open \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func saveBuffer(as format: BufferExportFormat) {
        guard let buffer else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        switch format {
        case .binary:
            panel.nameFieldStringValue = buffer.suggestedBaseName + ".bin"
            panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        case .intelHex:
            panel.nameFieldStringValue = buffer.suggestedBaseName + ".hex"
            panel.allowedContentTypes = [UTType(filenameExtension: "hex") ?? .plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .binary: try buffer.data.write(to: url, options: .atomic)
            case .intelHex: try IntelHex.encode(buffer.data).write(to: url, atomically: true, encoding: .ascii)
            }
            self.buffer?.modified = false
            succeed("Saved \(url.lastPathComponent)")
        } catch {
            fail("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Buffer analysis (find, compare, trim/pad)

    func clearMarks() { marks = nil }

    /// Finds every occurrence of a hex byte pattern ("DE AD BE EF") or text.
    func find(_ query: String, asHex: Bool) {
        guard let buffer else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { marks = nil; return }

        let needle: [UInt8]
        if asHex {
            guard let bytes = Self.parseHexBytes(trimmed), !bytes.isEmpty else {
                NSSound.beep()
                lastOutcome = Outcome(success: false, message: "“\(trimmed)” isn't valid hex – use byte pairs like DE AD BE EF")
                return
            }
            needle = bytes
        } else {
            needle = Array(trimmed.utf8)
        }

        let data = buffer.data
        let base = data.startIndex
        let pattern = Data(needle)
        var indexes = IndexSet()
        var anchors: [Int] = []
        var searchRange = data.startIndex..<data.endIndex
        while anchors.count < 10_000, let r = data.range(of: pattern, in: searchRange) {
            indexes.insert(integersIn: (r.lowerBound - base)..<(r.upperBound - base))
            anchors.append(r.lowerBound - base)
            searchRange = (r.lowerBound + 1)..<data.endIndex
        }
        if anchors.isEmpty {
            marks = nil
            NSSound.beep()
            lastOutcome = Outcome(success: false, message: "Not found: \(trimmed)")
        } else {
            marks = ByteMarks(kind: .find, title: "\(anchors.count)\(anchors.count == 10_000 ? "+" : "") matches",
                              indexes: indexes, anchors: anchors)
        }
    }

    /// Byte-by-byte comparison of the buffer with an image file.
    func compareWithFile() async {
        guard let buffer else { return }
        guard let url = chooseFile(title: "Compare the buffer with…") else { return }
        let other: Data
        do {
            other = try Self.loadImageData(url)
        } catch {
            fail("Could not open \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        let current = buffer.data
        let diff = await Task.detached(priority: .userInitiated) { BufferDiff(current, other) }.value
        let name = url.lastPathComponent
        if diff.differences.isEmpty {
            marks = nil
            if let note = diff.tailNote {
                fail("Contents match \(name), but \(note)")
            } else {
                succeed("Buffer is identical to \(name)")
            }
        } else {
            let count = diff.differences.count.formatted()
            marks = ByteMarks(kind: .diff, title: "\(count) bytes differ", indexes: diff.differences, anchors: diff.anchors)
            fail("\(count) bytes differ from \(name)\(diff.tailNote.map { "; " + $0 } ?? "")")
        }
    }

    /// Removes trailing fill bytes (e.g. the unused $FF tail of an image).
    func trimBuffer(fill: UInt8) {
        guard let buffer else { return }
        var bytes = [UInt8](buffer.data)
        while bytes.count > 1, bytes.last == fill { bytes.removeLast() }
        let removed = buffer.data.count - bytes.count
        guard removed > 0 else {
            lastOutcome = Outcome(success: false, message: String(format: "No trailing $%02X bytes to trim", fill))
            return
        }
        replaceBufferData(Data(bytes), note: String(format: "Trimmed %@ of trailing $%02X", Self.size(removed), fill))
    }

    /// Pads the buffer up to the selected chip's size.
    func padBuffer(fill: UInt8) {
        guard let buffer, let size = deviceInfo?.memoryBytes, size > buffer.data.count else {
            lastOutcome = Outcome(success: false, message: "Buffer is already as large as the chip")
            return
        }
        var data = buffer.data
        data.append(contentsOf: repeatElement(fill, count: size - data.count))
        replaceBufferData(data, note: String(format: "Padded to %@ with $%02X", Self.size(size), fill))
    }

    var canPadBuffer: Bool {
        guard let buffer, let size = deviceInfo?.memoryBytes else { return false }
        return size > buffer.data.count
    }

    private func replaceBufferData(_ data: Data, note: String) {
        guard let old = buffer else { return }
        setBuffer(ChipBuffer(data: data, origin: old.origin, extraFiles: old.extraFiles, modified: true))
        succeed(note)
    }

    /// "DE AD be ef", "0xDEADBEEF", "de,ad" → bytes.
    static func parseHexBytes(_ text: String) -> [UInt8]? {
        var cleaned = text.lowercased().replacingOccurrences(of: "0x", with: "")
        cleaned.removeAll { " ,:-$\t".contains($0) }
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    func revealExtraFiles() {
        guard let files = buffer?.extraFiles, !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    private func setBuffer(_ newBuffer: ChipBuffer) {
        buffer = newBuffer
        bufferStats = nil
        marks = nil
        let id = newBuffer.id
        let data = newBuffer.data
        Task {
            let stats = await Task.detached(priority: .userInitiated) { BufferStats(data) }.value
            if self.buffer?.id == id { self.bufferStats = stats }
        }
    }

    // MARK: - Suggestions & retry

    /// Applies the suggested fix (saved for this chip) and runs the failed operation again.
    func applySuggestion() async {
        guard let action = suggestion?.action else { return }
        switch action {
        case .ignoreIDError: options.ignoreIDError = true
        case .ignoreSizeError: options.ignoreSizeError = true
        case .padToChip: padBuffer(fill: 0xFF)
        }
        saveOptions()
        suggestion = nil
        await retryLastOperation()
    }

    func dismissSuggestion() { suggestion = nil }

    func retryLastOperation() async {
        guard let operation = lastOperation else { return }
        switch operation {
        case .read: await readChip()
        case .writeBuffer: pendingConfirmation = .writeBuffer
        case .writeFile(let url): pendingConfirmation = .writeFile(url)
        case .verifyBuffer: await verifyBuffer()
        case .verifyFile(let url): await verifyFile(url)
        case .blankCheck: await blankCheck()
        case .erase: pendingConfirmation = .erase
        case .readID: await readID()
        case .burnBuffer: pendingConfirmation = .burnBuffer
        case .burnFile(let url): pendingConfirmation = .burnFile(url)
        }
    }

    /// Turns common minipro failures into plain advice and, where safe, a fix.
    private func makeSuggestion(for result: CommandResult) -> FixSuggestion? {
        let text = result.lines.joined(separator: "\n").lowercased()

        if text.contains("overcurrent") || text.contains("over current") || text.contains("short circuit") {
            return FixSuggestion(hint: "Overcurrent protection tripped. The chip is probably the wrong way round, in the wrong position, or the wrong part is selected – check the socket diagram.")
        }

        if text.contains("id mismatch") || text.contains("invalid chip id") || text.contains("chip id") && text.contains("expected") {
            let ids = Self.hexValues(in: text)
            if let got = ids.last, got == 0 || got == 0xFF || got == 0xFFFF || got == 0xFFFFFF || got == 0xFFFF_FFFF {
                return FixSuggestion(hint: "The chip didn't answer the ID query. Check the orientation, that the lever is closed and that pins make contact.")
            }
            let detail = ids.count >= 2 ? String(format: " (expected 0x%llX, got 0x%llX)", ids[ids.count - 2], ids[ids.count - 1]) : ""
            return FixSuggestion(
                hint: "The chip reports a different ID\(detail). Clones and second-source parts often do – if you're sure it's the right chip, ignore the ID for it.",
                action: .ignoreIDError,
                actionLabel: "Ignore ID for This Chip & Retry")
        }

        if text.contains("file size") || text.contains("size mismatch") {
            if lastOperation?.usesBuffer == true, canPadBuffer {
                return FixSuggestion(hint: "The image is smaller than the chip. Pad it with $FF to the chip's size, which is what an erased chip contains anyway.",
                                     action: .padToChip, actionLabel: "Pad Buffer & Retry")
            }
            return FixSuggestion(hint: "The image size doesn't match the chip. If that's intended (e.g. a smaller image in a bigger chip), ignore the size for this chip.",
                                 action: .ignoreSizeError, actionLabel: "Ignore Size for This Chip & Retry")
        }

        if text.contains("verification failed") || text.contains("verify error") || text.contains("mismatch at") {
            return FixSuggestion(hint: "Some bytes didn't verify. For UV EPROMs this usually means the chip wasn't fully erased – erase it longer and blank-check first. If it was blank, try a higher VPP or a longer pulse under Programming voltages in the inspector. A stability read shows whether reads are consistent.")
        }
        return nil
    }

    private static func hexValues(in text: String) -> [UInt64] {
        guard let regex = try? NSRegularExpression(pattern: "0x([0-9a-f]+)") else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            UInt64(ns.substring(with: $0.range(at: 1)), radix: 16)
        }
    }

    /// Asks before an edited (trimmed/padded, unsaved) buffer gets replaced.
    private func confirmDiscardEdits() -> Bool {
        guard let buffer, buffer.modified else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard changes to \(buffer.title)?"
        alert.informativeText = "The buffer was trimmed or padded and hasn't been saved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Console

    func clearLog() { log.removeAll() }

    func copyLog() {
        let text = log.map { entry in
            let time = entry.date.formatted(date: .omitted, time: .standard)
            return "[\(time)] \(entry.text)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyLastCommand() {
        guard let lastCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastCommand, forType: .string)
    }

    private func appendLog(_ kind: LogEntry.Kind, _ text: String) {
        log.append(LogEntry(kind: kind, text: text))
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    // MARK: - Execution

    /// Runs minipro. All invocations are serialized: the programmer only talks
    /// to one process at a time, so a user action waits for a background poll
    /// to finish, while background polls are skipped if anything is running.
    @discardableResult
    private func execute(
        _ args: [String],
        title: String? = nil,
        echo: Bool = true,
        visible: Bool = true,
        skipIfBusy: Bool = false,
        timeout: Duration? = nil,
        stages: Int = 1
    ) async -> CommandResult? {
        guard let executable = miniproURL else {
            if visible { fail("minipro not found – set its path in Settings") }
            return nil
        }
        if skipIfBusy {
            guard !processRunning else { return nil }
        } else {
            while processRunning { try? await Task.sleep(for: .milliseconds(50)) }
        }

        processRunning = true
        if visible {
            isBusy = true
            activity = Activity(title: title ?? "Running minipro", stages: max(stages, 1))
        }
        defer {
            processRunning = false
            current = nil
            if visible {
                isBusy = false
                activity = nil
            }
        }

        let args = Self.longOptions(args)
        if echo {
            let line = Self.shellLine(executable.path, args)
            lastCommand = line
            appendLog(.command, "$ " + line)
        }

        let process: RunningProcess
        do {
            process = try RunningProcess(executable: executable, arguments: args)
        } catch {
            fail("Could not launch minipro: \(error.localizedDescription)")
            return nil
        }
        current = process

        // Watchdog: background queries must never block the queue (e.g. if
        // minipro unexpectedly waits for input). Long user operations get none.
        let started = ContinuousClock.now
        let watchdog: Task<Void, Never>? = timeout.map { limit in
            Task { [weak process] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                process?.interrupt()
            }
        }
        defer { watchdog?.cancel() }

        var result = CommandResult()
        for await event in process.events {
            switch event {
            case .line(let text, let source):
                result.lines.append(text)
                if source == .stdout { result.stdout.append(text) } else { result.stderr.append(text) }
                if echo { appendLog(source == .stdout ? .stdout : .stderr, text) }
                updateActivity(with: text)
            case .transient(let text, _):
                updateActivity(with: text)
            case .exited(let status):
                result.status = status
            }
        }
        if let timeout, ContinuousClock.now - started >= timeout {
            appendLog(.error, "minipro \(args.joined(separator: " ")) did not finish within \(timeout) and was stopped.")
        }
        return result
    }

    /// One overall progress value across minipro's stages ("Erasing...",
    /// "Writing Code...", "Reading Code..." for verify), never moving backwards.
    private func updateActivity(with text: String) {
        guard var a = activity else { return }
        a.detail = text
        if let label = OutputParser.stageLabel(in: text) {
            if a.stageLabel == nil {
                a.stageLabel = label
            } else if label != a.stageLabel {
                a.stageLabel = label
                a.stageIndex += 1
            }
            if label.lowercased().contains("eras"), !a.countedErase {
                a.countedErase = true
                a.stages += 1
            }
        }
        let stageProgress = OutputParser.progress(in: text) ?? (text.hasSuffix("OK") ? 1 : nil)
        if let p = stageProgress {
            let index = Double(min(a.stageIndex, a.stages - 1))
            let overall = (index + p) / Double(a.stages)
            a.progress = min(max(overall, a.progress ?? 0), 1)
        }
        activity = a
    }

    // MARK: - Helpers

    private func requireDevice() -> String? {
        guard canUseProgrammer else { return nil }
        guard let device = selectedDevice else {
            fail("Select a chip first")
            return nil
        }
        return device
    }

    private func succeed(_ message: String, sound: Bool = false) {
        lastOutcome = Outcome(success: true, message: message)
        suggestion = nil
        appendLog(.success, "✓ " + message)
        if sound { playSound("Glass") }
    }

    private func fail(_ message: String, _ result: CommandResult? = nil, sound: Bool = false) {
        let full = result.map { "\(message): \($0.failureReason)" } ?? message
        lastOutcome = Outcome(success: false, message: full)
        suggestion = result.flatMap { makeSuggestion(for: $0) }
        appendLog(.error, "✗ " + full)
        if let hint = suggestion?.hint { appendLog(.info, "Hint: " + hint) }
        if let result, Self.looksLikeUSBProblem(result) {
            appendLog(.info, "Tip: unplug and replug the programmer. macOS can suspend USB devices after sleep, and hubs or long cables cause transfer errors.")
        }
        if sound { playSound("Basso") }
    }

    private static func looksLikeUSBProblem(_ result: CommandResult) -> Bool {
        let text = result.lines.joined(separator: " ").lowercased()
        return ["usb", "no programmer", "io error", "timed out", "timeout", "transfer"].contains { text.contains($0) }
    }

    private func playSound(_ name: String) {
        let enabled = UserDefaults.standard.object(forKey: DefaultsKey.completionSounds) as? Bool ?? true
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func chooseFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func writeTemp(_ data: Data, name: String) -> URL? {
        let dir = Self.workDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(UUID().uuidString)-\(name)")
            try data.write(to: url)
            return url
        } catch {
            fail("Could not write temporary file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Short flags → minipro's long option names, for readable commands in the
    /// console (`--device X --no_id_error --write file`). Only names confirmed
    /// against minipro are mapped; anything else stays in its short form.
    private static let longOptionNames: [String: String] = [
        "-p": "--device",
        "-r": "--read",
        "-w": "--write",
        "-m": "--verify",
        "-b": "--blank_check",
        "-E": "--erase",
        "-x": "--skip_id",
        "-y": "--no_id_error",
        "-s": "--no_size_error",
        "-v": "--skip_verify",
        "-z": "--pin_check",
        "-t": "--hardware_check",
        "-k": "--presence_check",
    ]

    static func longOptions(_ args: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < args.count {
            // "-o vpp=12.5" → "--vpp=12.5" (documented long form)
            if args[i] == "-o", i + 1 < args.count, args[i + 1].contains("=") {
                out.append("--" + args[i + 1])
                i += 2
                continue
            }
            out.append(longOptionNames[args[i]] ?? args[i])
            i += 1
        }
        return out
    }

    static var workDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ZIFburn", isDirectory: true)
    }

    static func size(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .memory))
    }

    static func shellLine(_ executable: String, _ args: [String]) -> String {
        ([executable] + args).map { arg in
            let safe = arg.allSatisfy { $0.isLetter || $0.isNumber || "-_./@:+=".contains($0) }
            return safe && !arg.isEmpty ? arg : "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}
