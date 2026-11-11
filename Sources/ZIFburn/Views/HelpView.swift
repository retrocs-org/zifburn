import AppKit
import SwiftUI

/// Help › ZIFburn Help (⌘?). A short, practical guide; no external help book.
@MainActor
struct HelpView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZIFburn Help")
                            .font(.largeTitle.weight(.semibold))
                        Text(AppInfo.versionString)
                            .foregroundStyle(.secondary)
                    }
                }

                section("Getting started", "play.circle") {
                    step(1, "Install minipro with **brew install minipro** and plug in your programmer. The toolbar badge turns green when it's found.")
                    step(2, "Pick the **programmer** in the first select box. Auto follows the connected programmer, or shows every database when none is plugged in.")
                    step(3, "Pick the **chip** in the second box (⌘L) and type to search, e.g. `27c512 dip`. Star chips you use often.")
                    step(4, "Check the **Socket** diagram in the inspector, insert the chip with pin 1 where it shows, and close the lever.")
                    step(5, "**Read** (⌘R) to fill the buffer, or open an image (⌘O) and **Write** it (⇧⌘W). Writes are erased and verified unless you turn that off in the inspector.")
                }

                section("Workflows", "arrow.triangle.branch") {
                    item("Burn (⇧⌘B)", "Blank check, write and verify in one go – the classic EPROM sequence. Stops if the chip isn't blank.")
                    item("Burn ROM set", "Pick all images of a set, e.g. the -hi and -lo halves of a Kickstart ROM. ZIFburn asks for a chip for each and burns them in turn.")
                    item("Duplicate a chip (⇧⌘D)", "Reads a master chip, then asks for blank chips and writes a verified copy to each.")
                    item("Batch write", "Writes the buffer to one chip after another, with Retry, Stop and a pass/fail count.")
                    item("Stability check (⇧⌘R)", "Reads three times and compares. Unstable bytes are highlighted and the buffer keeps the majority vote. Good for old EPROMs.")
                    item("SPI flash auto-detect", "Tools › Auto-detect 8/16-pin identifies 25-series flash from its JEDEC ID.")
                    item("Per-chip options", "Inspector options are remembered for each chip and restored when you select it again.")
                    item("Pin contact check", "On the TL866II+ and T48, every operation first checks that all pins make contact. Toggle it in the inspector.")
                }

                section("The buffer", "square.grid.3x3") {
                    item("Find (⌘F)", "Search byte patterns such as DE AD BE EF, or switch to Text. Use ↑ ↓ to step through matches.")
                    item("Compare…", "Highlights every byte that differs from an image file, and tells you if an extra tail is just padding.")
                    item("Trim / Pad", "Strip trailing $FF/$00, or pad the image to the selected chip's size.")
                    item("Go to offset", "Type 1FF0, $1FF0 or 0x1FF0.")
                    item("Font size", "View › Larger / Smaller Hex Font (⌘+ ⌘− ⌘0).")
                }

                section("Keyboard shortcuts", "keyboard") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        shortcut("⌘L", "Select chip")
                        shortcut("⌘R", "Read")
                        shortcut("⇧⌘W", "Write buffer")
                        shortcut("⇧⌘B", "Burn buffer (blank check + write + verify)")
                        shortcut("⌘Y", "Verify against buffer")
                        shortcut("⌘B", "Blank check")
                        shortcut("⇧⌘⌫", "Erase")
                        shortcut("⌘I", "Read chip ID")
                        shortcut("⇧⌘D", "Duplicate chip")
                        shortcut("⇧⌘R", "Read with stability check")
                        shortcut("⌘K", "Check programmer connection")
                        shortcut("⌘.", "Cancel the running operation")
                        shortcut("⌘O / ⌘S", "Open image / save buffer")
                    }
                }

                section("Amiga Kickstart ROMs", "memorychip") {
                    item("27C400 / 27C4096 EPROMs", "Select e.g. AM27C4096@DIP40. Clones often report a different chip ID, so turn on “Ignore chip ID mismatch” (--no_id_error) and “Skip chip ID check” (--skip_id) in the inspector.")
                    item("32-bit machines (A1200, A4000, A3000)", "Use Burn ROM Set with the -hi and -lo files and label each chip as it comes out of the socket.")
                    item("27C160 / 27C322 / 27C800 (42-pin)", "Use the 27C160/322/400/800 adapter: choose it in the inspector's Adapter section, pick the chip and press Read, Burn, Verify or Blank. ZIFburn asks you to set the DIP switches for each 512 KB part, following the adapter's own table (Part 001 = all ON). Put the adapter in with both levers side by side, and the EPROM in the lowest position with pin 1 nearest the adapter's lever.")
                    item("Make a backup first", "Read (⌘R) the original ROMs and save them (⌘S) before burning anything.")
                }

                section("Troubleshooting", "wrench.and.screwdriver") {
                    item("“No programmer”", "Replug the USB cable and avoid unpowered hubs. macOS can suspend USB devices after sleep.")
                    item("A database is greyed out", "Your minipro version doesn't know that programmer family (e.g. T76). Run brew upgrade minipro.")
                    item("Chip ID mismatch", "Check the exact part number and the placement. Clones often report odd IDs. As a last resort, enable “Ignore chip ID mismatch”.")
                    item("A yellow hint appears under the buffer", "ZIFburn recognised the error. Read the hint. If it offers a button (e.g. Ignore ID for This Chip & Retry), that fix is saved for the chip and the operation runs again.")
                    item("New chips don't show up", "The chip list is cached per minipro version. Use Programmer › Reload Device List after changing minipro's database.")
                    item("Anything else", "Every action is printed in the console as a real minipro command. Copy it with the </> button and run it in Terminal to compare.")
                }

                section("Links", "link") {
                    Link("minipro project (GitLab)", destination: URL(string: "https://gitlab.com/DavidGriffith/minipro")!)
                    Link("minipro manual page", destination: URL(string: "https://gitlab.com/DavidGriffith/minipro/-/blob/master/man/minipro.1")!)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .themedBackground(theme, theme.palette?.background)
    }

    private func section<Content: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accent)
            content()
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.accent.opacity(0.2)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func item(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .gridColumnAlignment(.trailing)
            Text(action)
        }
    }
}
