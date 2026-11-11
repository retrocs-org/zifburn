import XCTest
@testable import ZIFburn

final class OutputParserTests: XCTestCase {
    func testCleanStripsANSIAndWhitespace() {
        XCTAssertEqual(OutputParser.clean("\u{1B}[KReading Code...  42%  "), "Reading Code...  42%")
    }

    func testProgress() throws {
        XCTAssertEqual(try XCTUnwrap(OutputParser.progress(in: "Writing Code...  42%")), 0.42, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(OutputParser.progress(in: "Erasing... 100%")), 1.0, accuracy: 0.0001)
        XCTAssertNil(OutputParser.progress(in: "Verification OK"))
    }

    func testStageLabel() {
        XCTAssertEqual(OutputParser.stageLabel(in: "Writing Code...  42%"), "Writing Code")
        XCTAssertEqual(OutputParser.stageLabel(in: "Reading Code...  0.18Sec  OK"), "Reading Code")
        XCTAssertNil(OutputParser.stageLabel(in: "Verification OK"))
    }

    func testVersion() {
        let lines = ["minipro version 0.7.4     A free and open TL866 series programmer"]
        XCTAssertEqual(OutputParser.version(from: lines), "0.7.4")
    }

    func testParseSize() {
        XCTAssertEqual(OutputParser.parseSize("32768 Bytes"), 32768)
        XCTAssertEqual(OutputParser.parseSize("0 Bytes + 131102 Bytes"), 131102)   // NAND
        XCTAssertEqual(OutputParser.parseSize("2048 Words + 128 Bytes"), 4096)     // PIC code + EEPROM
        XCTAssertEqual(OutputParser.parseSize("0x4000 Words"), 32768)
        XCTAssertNil(OutputParser.parseSize("0 Bytes"))
    }

    func testDeviceInfoSkipsBannerAndName() throws {
        let lines = [
            "Found T48 00.1.31 (0x11f)",
            "Name: AT28C256",
            "Memory: 32768 Bytes",
            "Package: DIP28",
            "Protocol: 0x05",
        ]
        let info = try XCTUnwrap(OutputParser.deviceInfo(from: lines, fallbackName: "fallback"))
        XCTAssertEqual(info.name, "AT28C256")
        XCTAssertEqual(info.memoryBytes, 32768)
        XCTAssertEqual(info.package, "DIP28")
        XCTAssertEqual(info.fields.first?.key, "Memory")
        XCTAssertFalse(info.fields.contains { $0.key == "Name" })
    }

    func testDeviceInfoNilWithoutNameBlock() {
        XCTAssertNil(OutputParser.deviceInfo(from: ["Error: unknown device"], fallbackName: "X"))
    }

    func testDeviceListDropsInteractivePrompt() {
        let lines = [
            "No device found. Which database do you want to display?",
            "1) TL866A/CS",
            "2) TL866II+/T48/T56",
            "3) Abort",
            "4000",
            "4001",
            "4000",
        ]
        XCTAssertEqual(OutputParser.deviceList(from: lines), ["4000", "4001"])
    }

    func testProgrammerConnected() {
        let status = OutputParser.programmer(from: ["Found T48 00.1.31 (0x11f)"], status: 0)
        XCTAssertEqual(status, .connected(model: "T48", firmware: "00.1.31", qFlag: "t48"))
    }

    func testProgrammerDisconnected() {
        let status = OutputParser.programmer(from: ["No programmer found."], status: 1)
        XCTAssertFalse(status.isConnected)
        XCTAssertNil(status.qFlag)
    }
}

final class FormatTests: XCTestCase {
    func testCRC32KnownVector() {
        XCTAssertEqual(Checksum.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testSum16AndUniformByte() {
        XCTAssertEqual(Checksum.sum16(Data([0xFF, 0x01])), 0x0100)
        XCTAssertEqual(Checksum.uniformByte(Data(repeating: 0xFF, count: 64)), 0xFF)
        XCTAssertNil(Checksum.uniformByte(Data([0xFF, 0x00])))
        XCTAssertNil(Checksum.uniformByte(Data()))
    }

    func testIntelHexRoundTripAcross64K() throws {
        var bytes = [UInt8](repeating: 0, count: 70_000)
        for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        let data = Data(bytes)
        XCTAssertEqual(try IntelHex.decode(IntelHex.encode(data)), data)
    }

    func testIntelHexChecksum() throws {
        XCTAssertEqual(try IntelHex.decode(":0100000041BE\n:00000001FF\n"), Data([0x41]))
        XCTAssertThrowsError(try IntelHex.decode(":0100000041BF\n"))
    }

    func testBufferDiff() {
        let diff = BufferDiff(Data([1, 2, 3, 4]), Data([1, 9, 3, 8, 0xFF, 0xFF]))
        XCTAssertEqual(Array(diff.differences), [1, 3])
        XCTAssertEqual(diff.anchors, [1, 3])
        XCTAssertEqual(diff.tailNote, "the file is 2 bytes longer (padding only)")
    }

    func testBufferDiffIdentical() {
        let diff = BufferDiff(Data([1, 2, 3]), Data([1, 2, 3]))
        XCTAssertTrue(diff.differences.isEmpty)
        XCTAssertNil(diff.tailNote)
    }

    func testStabilityMajorityVote() {
        let analysis = StabilityAnalysis([Data([1, 2, 3]), Data([1, 5, 3]), Data([1, 2, 7])])
        XCTAssertEqual(analysis.consensus, Data([1, 2, 3]))
        XCTAssertEqual(Array(analysis.unstable), [1, 2])
    }

    func testHexRow() {
        let row = HexFormatter.row(Data([0x41, 0x00, 0x7E]), row: 0, addressDigits: 4)
        XCTAssertEqual(row.address, "0000")
        XCTAssertEqual(row.bytes, [0x41, 0x00, 0x7E])
        XCTAssertTrue(row.hex.hasPrefix("41 00 7E "))
        XCTAssertEqual(row.ascii, "A·~")
    }
}

final class DeviceNameTests: XCTestCase {
    func testRepairsMisencodedParentheses() {
        XCTAssertEqual(DeviceName.display("£¨GSTO)GTS1G3D1S-WS(x1+ISP)@BGA24"), "(GSTO)GTS1G3D1S-WS(x1+ISP)@BGA24")
    }

    func testLeavesASCIIUntouched() {
        XCTAssertEqual(DeviceName.display("AM27C4096@DIP40"), "AM27C4096@DIP40")
    }
}

final class SocketTests: XCTestCase {
    func testBottomJustifiedOn48PinSocket() throws {
        let placement = try XCTUnwrap(ChipPlacement(package: "DIP8", socket: .forProgrammer("t56")))
        XCTAssertEqual(placement.chipPins, 8)
        XCTAssertEqual(placement.firstRow, 20)   // ZIF pins 21–24 + 25–28
    }

    func testTL866ChipsGoToTheLeverEnd() throws {
        // Verified on a TL866II Plus: lever bottom-right, chips at the lever end, notch down.
        let socket = SocketLayout.forProgrammer("tl866ii")
        let placement = try XCTUnwrap(ChipPlacement(package: "DIP8", socket: socket))
        XCTAssertEqual(placement.firstRow, 16)
        XCTAssertEqual(placement.pin1Row(notchUp: socket.notchUp), 19)
        XCTAssertTrue(socket.leverBottomRight)
    }

    @MainActor
    func testArticles() {
        XCTAssertEqual(ZIFDiagram.article(8), "an")
        XCTAssertEqual(ZIFDiagram.article(18), "an")
        XCTAssertEqual(ZIFDiagram.article(28), "a")
        XCTAssertEqual(ZIFDiagram.article(40), "a")
    }

    func testTopJustifiedFullSocket() throws {
        let placement = try XCTUnwrap(ChipPlacement(package: "DIP40", socket: .forProgrammer("t48")))
        XCTAssertEqual(placement.firstRow, 0)
    }

    func testAdapterPackages() {
        XCTAssertEqual(adapterPackage(device: "24AA512@DFN8", reportedPackage: "DIP8"), "DFN8")
        XCTAssertEqual(adapterPackage(device: "W25Q128@SOIC8", reportedPackage: "DIP8"), "SOIC8")
        XCTAssertNil(adapterPackage(device: "AM27C4096@DIP40", reportedPackage: "DIP40"))
        XCTAssertNil(adapterPackage(device: "25AA080C", reportedPackage: "DIP8"))
        XCTAssertNil(adapterPackage(device: "X@PLCC32", reportedPackage: "PLCC32"))
    }

    func testNonFittingPackages() {
        XCTAssertNil(ChipPlacement(package: "PLCC32", socket: .forProgrammer("t48")))
        XCTAssertNil(ChipPlacement(package: "DIP41", socket: .forProgrammer("tl866a")))
        XCTAssertNil(ChipPlacement(package: "DIP48", socket: .forProgrammer("t48")))
        XCTAssertNil(ChipPlacement(package: nil, socket: .forProgrammer(nil)))
    }
}

final class AdapterTests: XCTestCase {
    private let adapter = AdapterProfile.eprom16

    private func target(_ id: String) -> AdapterProfile.Target {
        adapter.targets.first { $0.id == id }!
    }

    func testBankCounts() {
        XCTAssertEqual(AdapterProfile.bits(for: 1), 0)
        XCTAssertEqual(AdapterProfile.bits(for: 2), 1)
        XCTAssertEqual(AdapterProfile.bits(for: 4), 2)
        XCTAssertEqual(AdapterProfile.bits(for: 8), 3)
        XCTAssertEqual(adapter.size(of: target("27C322")), 4 * 1024 * 1024)
        XCTAssertEqual(adapter.size(of: target("27C800")), 1024 * 1024)
    }

    func testSwitchesSelectBank() {
        XCTAssertEqual(adapter.switches(bank: 5, target: target("27C322"), onMeansHigh: true), [true, false, true])
        XCTAssertEqual(adapter.switches(bank: 5, target: target("27C322"), onMeansHigh: false), [false, true, false])
        // 27C800 only uses A18; A19/A20 stay "low".
        XCTAssertEqual(adapter.switches(bank: 1, target: target("27C800"), onMeansHigh: true), [true, false, false])
        XCTAssertEqual(adapter.switches(bank: 0, target: target("27C400"), onMeansHigh: true), [false, false, false])
    }

    func testMatchesOfficialDIPTable() {
        // mafe72 adapter table: Part 001…008 → A18/A19/A20, 1 = switch ON.
        let table: [[Bool]] = [
            [true, true, true], [false, true, true], [true, false, true], [false, false, true],
            [true, true, false], [false, true, false], [true, false, false], [false, false, false],
        ]
        for bank in 0..<8 {
            XCTAssertEqual(adapter.switches(bank: bank, target: target("27C322"), onMeansHigh: adapter.defaultOnMeansHigh),
                           table[bank], "Part \(bank + 1)")
        }
        // 27C400 = Part 001 only: all ON. 27C800 Part 002 = A18 OFF, A19/A20 ON.
        XCTAssertEqual(adapter.switches(bank: 0, target: target("27C400"), onMeansHigh: false), [true, true, true])
        XCTAssertEqual(adapter.switches(bank: 1, target: target("27C800"), onMeansHigh: false), [false, true, true])
        XCTAssertEqual(AdapterProfile.partName(2), "Part 003")
    }

    func testDescribe() {
        XCTAssertEqual(
            adapter.describe(bank: 1, target: target("27C160"), onMeansHigh: true),
            "DIP 1 (A18) ON, 2 (A19) OFF, 3 (A20) OFF · slide switch on “other”"
        )
    }

    @MainActor
    func testSwapBytes16() {
        XCTAssertEqual(AppModel.swapBytes16(Data([1, 2, 3, 4, 5])), Data([2, 1, 4, 3, 5]))
    }
}

final class OptionsTests: XCTestCase {
    func testFlagsOnlyWhereTheyApply() {
        var options = ProgrammingOptions()
        options.ignoreIDError = true
        options.skipVerify = true
        options.page = .data

        let write = options.arguments(for: .write)
        XCTAssertTrue(write.contains("-y"))
        XCTAssertTrue(write.contains("-v"))
        XCTAssertFalse(write.contains("-x"))
        XCTAssertEqual(options.arguments(for: .read), ["-y", "-c", "data"])
        XCTAssertEqual(options.arguments(for: .pinCheck), [])
        XCTAssertFalse(options.arguments(for: .verify).contains("-v"))
    }

    func testVoltageOptionsOnlyOnWrite() {
        var options = ProgrammingOptions()
        options.vpp = 12.5
        options.vdd = 3.3
        options.pulse = 50
        let write = options.arguments(for: .write)
        XCTAssertEqual(Array(write.prefix(6)), ["-o", "vpp=12.5", "-o", "vdd=3.3", "-o", "pulse=50"])
        XCTAssertFalse(options.arguments(for: .verify).contains("-o"))
        XCTAssertFalse(options.arguments(for: .read).contains("-o"))
        XCTAssertTrue(options.hasVoltageOverrides)
    }

    func testVoltageFormattingAndSteps() {
        XCTAssertEqual(VoltageTable.format(13), "13")
        XCTAssertEqual(VoltageTable.format(12.5), "12.5")
        XCTAssertEqual(VoltageTable.format(3.3), "3.3")
        XCTAssertTrue(VoltageTable.vppTL866II.contains(13.5))
        XCTAssertFalse(VoltageTable.vppTL866A.contains(13))   // TL866A/CS has no 13 V step
    }

    func testDecodesOptionsSavedByOlderBuilds() throws {
        let json = Data(#"{"page":"auto","skipErase":true}"#.utf8)
        let options = try JSONDecoder().decode(ProgrammingOptions.self, from: json)
        XCTAssertTrue(options.skipErase)
        XCTAssertTrue(options.pinCheckFirst)   // new switch gets its default
        XCTAssertNil(options.vpp)
        XCTAssertEqual(options.icsp, .off)
    }

    func testRoundTrip() throws {
        var options = ProgrammingOptions()
        options.icsp = .withVCC
        options.ignoreSizeError = true
        let decoded = try JSONDecoder().decode(ProgrammingOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded, options)
    }
}

final class AppModelHelperTests: XCTestCase {
    @MainActor
    func testLongOptionNames() {
        XCTAssertEqual(
            AppModel.longOptions(["-p", "AM27C4096@DIP40", "-w", "a.bin", "-y", "-a", "8"]),
            ["--device", "AM27C4096@DIP40", "--write", "a.bin", "--no_id_error", "-a", "8"]
        )
    }

    @MainActor
    func testLongFormForDashO() {
        XCTAssertEqual(
            AppModel.longOptions(["-p", "AM27C4096@DIP40", "-w", "k.bin", "-o", "vpp=12.5", "-o", "pulse=50", "-x"]),
            ["--device", "AM27C4096@DIP40", "--write", "k.bin", "--vpp=12.5", "--pulse=50", "--skip_id"]
        )
    }

    @MainActor
    func testParseHexBytes() {
        XCTAssertEqual(AppModel.parseHexBytes("DE AD be,ef"), [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(AppModel.parseHexBytes("0xDEADBEEF"), [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertNil(AppModel.parseHexBytes("ABC"))
        XCTAssertNil(AppModel.parseHexBytes("ZZ"))
    }

    @MainActor
    func testShellLineQuotes() {
        XCTAssertEqual(AppModel.shellLine("minipro", ["--write", "my rom.bin"]), "minipro --write 'my rom.bin'")
    }
}

final class ReleaseRegressionTests: XCTestCase {
    private func record(_ type: UInt8, address: UInt16 = 0, payload: [UInt8] = []) -> String {
        var bytes = [UInt8(payload.count), UInt8(address >> 8), UInt8(address & 255), type] + payload
        bytes.append(0 &- bytes.reduce(0, &+))
        return ":" + bytes.map { String(format: "%02X", $0) }.joined() + "\n"
    }

    func testRejectsMissingEndAndTrailingRecords() {
        XCTAssertThrowsError(try IntelHex.decode(record(0, payload: [1])))
        XCTAssertThrowsError(try IntelHex.decode(record(1) + record(0, payload: [1])))
        XCTAssertThrowsError(try IntelHex.decode(""))
    }

    func testRejectsMalformedAndUnknownRecordTypes() {
        for text in [record(1, payload: [1]), record(2, payload: [0]),
                     record(4, address: 1, payload: [0, 0]), record(3, payload: [0]), record(6)] {
            XCTAssertThrowsError(try IntelHex.decode(text + record(1)))
        }
    }

    func testRejectsSparseAddressesBeforeAllocation() {
        let high = record(4, payload: [255, 255]) + record(0, payload: [1]) + record(1)
        XCTAssertThrowsError(try IntelHex.decode(high))
        XCTAssertThrowsError(try IntelHex.decode(record(0, address: 16, payload: [1]) + record(1), maximumBytes: 16))
        XCTAssertThrowsError(try IntelHex.decode(record(0, address: 65535, payload: [1, 2]) + record(1)))
    }

    func testValidSegmentAndStartAddressRecords() throws {
        let text = record(2, payload: [0, 1]) + record(3, payload: [0, 0, 0, 0])
            + record(5, payload: [0, 0, 0, 0]) + record(0, payload: [65]) + record(1)
        XCTAssertEqual(try IntelHex.decode(text), Data(repeating: 255, count: 16) + Data([65]))
    }

    @MainActor
    func testSRecordBufferImportIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["image.srec", "image.s19", "image.bin"] {
            let url = directory.appendingPathComponent(name)
            try Data("S0030000FC\nS9030000FC\n".utf8).write(to: url)
            XCTAssertThrowsError(try AppModel.loadImageData(url))
        }
    }

    @MainActor
    func testBurnConfirmationWarnsWhenVerificationIsDisabled() {
        let model = AppModel()
        let original = model.options
        defer { model.options = original }
        model.options.skipVerify = true
        XCTAssertTrue(model.confirmationIsDestructive(.burnBuffer))
        XCTAssertTrue(model.confirmationMessage(.burnBuffer).contains("will not be verified"))
        XCTAssertEqual(model.confirmationActionLabel(.burnBuffer), "Burn")
    }
}
