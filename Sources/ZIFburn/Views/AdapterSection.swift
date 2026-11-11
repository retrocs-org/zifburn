import SwiftUI

/// Inspector section for bank-switched adapters such as the
/// 27C160/322/400/800 board: pick the chip, see the DIP switch setting for
/// the current bank, and run read / burn / verify / blank check bank by bank.
@MainActor
struct AdapterSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model

        Section("Adapter") {
            Picker("Adapter", selection: $model.adapterID) {
                Text("None").tag("")
                ForEach(AdapterProfile.all) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }

            if let adapter = model.adapter, let target = model.adapterTarget {
                Picker("Chip", selection: $model.adapterTargetID) {
                    ForEach(adapter.targets) { t in
                        Text("\(t.id) – \(AppModel.size(adapter.size(of: t)))\(t.banks > 1 ? ", \(t.banks) banks" : "")")
                            .tag(t.id)
                    }
                }

                let bank = model.adapterActiveBank ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 18) {
                        DIPSwitchView(
                            labels: adapter.switchLabels,
                            states: adapter.switches(bank: bank, target: target, onMeansHigh: model.adapterOnMeansHigh),
                            used: AdapterProfile.bits(for: target.banks)
                        )
                        SlideSwitchView(options: ["other", "27c322"], selected: target.modeSwitch)
                    }
                    Text(model.adapterActiveBank == nil
                         ? "\(AdapterProfile.partName(0)) shown. Each part is \(AppModel.size(adapter.bankSize)), programmed as \(DeviceName.display(adapter.device)) with the chip ID check off."
                         : "\(AdapterProfile.partName(bank)) of \(String(format: "%03d", target.banks))")
                        .font(.caption)
                        .foregroundStyle(model.adapterActiveBank == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.accent))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                Toggle("Switch ON = address line high", isOn: $model.adapterOnMeansHigh)
                    .help("Off matches the adapter's official table (Part 001 = all switches ON). Revision R_20231123 changed the polarity – flip this if Part 002 reads back the same as Part 001.")

                if adapter.guidePulse != nil || adapter.guideVPP != nil {
                    Button("Use the Adapter Guide's Pulse & VPP") { model.applyAdapterGuideSettings() }
                        .help("Saves a \(adapter.guidePulse.map { "\($0) µs pulse" } ?? "")\(adapter.guidePulse != nil && adapter.guideVPP != nil ? " and " : "")\(adapter.guideVPP.map { "\(VoltageTable.format($0)) V VPP" } ?? "") for \(DeviceName.display(adapter.device)), as the adapter's README recommends.")
                }

                Label(adapter.insertion, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Swap byte order (16-bit)", isOn: $model.adapterSwapBytes)
                    .help("Swap the two bytes of every word on read and burn, for images stored in the other byte order.")

                HStack(spacing: 6) {
                    Button("Read") { model.startAdapterJob(.read) }
                    Button("Burn") { model.startAdapterJob(.burn) }
                        .disabled(model.buffer == nil)
                    Button("Verify") { model.startAdapterJob(.verify) }
                        .disabled(model.buffer == nil)
                    Button("Blank") { model.startAdapterJob(.blankCheck) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.canUseProgrammer)
            }
        }
    }
}

/// A row of red DIP switches; ON = knob up.
struct DIPSwitchView: View {
    let labels: [String]
    let states: [Bool]
    /// How many switches the current chip uses; the rest are dimmed.
    let used: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels.indices, id: \.self) { i in
                let on = i < states.count && states[i]
                VStack(spacing: 3) {
                    Text("\(i + 1)")
                        .font(.caption2.monospacedDigit())
                    ZStack(alignment: on ? .top : .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0xD7263D))
                            .frame(width: 18, height: 36)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 12, height: 15)
                            .padding(3)
                    }
                    Text(on ? "ON" : "OFF")
                        .font(.caption2.weight(.semibold))
                    Text(labels[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .opacity(i < used ? 1 : 0.4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Switch \(i + 1), \(labels[i]), \(on ? "on" : "off")")
            }
        }
    }
}

/// The adapter's two-position slide switch.
struct SlideSwitchView: View {
    let options: [String]
    let selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Slide")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack(alignment: options.first == selected ? .leading : .trailing) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0x2A2C33))
                    .frame(width: 44, height: 18)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0xC9CDD6))
                    .frame(width: 18, height: 14)
                    .padding(.horizontal, 2)
            }
            Text(selected)
                .font(.caption2.weight(.semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide switch on \(selected)")
    }
}
