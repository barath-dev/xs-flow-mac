import FlowCore
import SwiftUI

/// Onboard settings, written to the mouse through the 2.4G dongle or USB cable.
struct HardwareView: View {
    @Environment(AppModel.self) private var model
    @State private var dpiLevels: [Int] = []
    @State private var activeLevel = 0
    @State private var confirmReset = false

    var body: some View {
        if let hardware = model.hardware {
            content(hardware)
        } else {
            ContentUnavailableView {
                Label("Connect the dongle or USB cable", systemImage: "cable.connector")
            } description: {
                Text("Over Bluetooth the XS Flow has no configuration channel, so DPI, polling rate, lighting and onboard buttons can only be changed through the 2.4G receiver or the cable. Software remapping in the other tabs works on any connection.")
            }
        }
    }

    @ViewBuilder
    private func content(_ hardware: HardwareController) -> some View {
        @Bindable var model = model
        Form {
            Section("Status") {
                if let s = model.hardwareStatus {
                    LabeledContent("Battery", value: "\(s.batteryPercent)%\(s.isCharging ? " (charging)" : "")")
                    LabeledContent("Polling rate", value: s.pollingRate.map { "\($0.hertz) Hz" } ?? "–")
                    LabeledContent("DPI level", value: "\(Int(s.dpiLevel) + 1)")
                    LabeledContent("Sensor", value: s.sensorName)
                } else {
                    Text("Waiting for the mouse… (move it to wake it up)").foregroundStyle(.secondary)
                }
                if let message = model.hardwareMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Polling rate") {
                let rates = PollingRate.supported(maxReportRate: model.hardwareStatus?.maxReportRate ?? 1)
                Picker("Report rate", selection: Binding(
                    get: { model.hardwareStatus?.pollingRate ?? .hz1000 },
                    set: { rate in model.runHardware("Setting \(rate.hertz) Hz") { try await $0.setPollingRate(rate) } }
                )) {
                    ForEach(rates, id: \.self) { Text("\($0.hertz) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("DPI levels") {
                ForEach(dpiLevels.indices, id: \.self) { i in
                    DPILevelRow(
                        index: i,
                        dpi: $dpiLevels[i],
                        activeLevel: $activeLevel,
                        maxDPI: maxDPI,
                        canRemove: dpiLevels.count > 1,
                        remove: {
                            dpiLevels.remove(at: i)
                            activeLevel = min(activeLevel, dpiLevels.count - 1)
                        }
                    )
                }
                HStack {
                    Button("Add Level") { dpiLevels.append(min((dpiLevels.last ?? 800) * 2, maxDPI)) }
                        .disabled(dpiLevels.count >= 8)
                    Spacer()
                    Button("Apply DPI") {
                        let levels = dpiLevels, level = activeLevel
                        model.hardwarePrefs.dpiLevels = levels
                        model.runHardware("Writing DPI") { try await $0.setDPI(levels: levels, currentLevel: level) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("The DPI button on the mouse cycles through these levels.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Onboard buttons") {
                ForEach(OnboardButton.allCases, id: \.self) { slot in
                    Picker(slot.displayName, selection: $model.hardwarePrefs.buttons[slot.rawValue - 1]) {
                        ForEach(ButtonCode.presets, id: \.code) { Text($0.name).tag($0.code) }
                        let current = model.hardwarePrefs.buttons[slot.rawValue - 1]
                        if !ButtonCode.presets.contains(where: { $0.code == current }) {
                            Text(current.displayName).tag(current)
                        }
                    }
                }
                HStack {
                    Button("Restore Defaults") {
                        model.hardwarePrefs.buttons = OnboardButton.allCases.map(\.factoryCode)
                    }
                    Spacer()
                    Button("Write to Mouse") {
                        let map = model.hardwarePrefs.buttons
                        model.runHardware("Writing button map") { try await $0.setButtons(map) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("Stored on the mouse itself, so it works on any computer and over Bluetooth. For shortcuts and per-app actions use the Buttons tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Lighting") {
                Picker("Effect", selection: $model.hardwarePrefs.lightingMode) {
                    ForEach(LightingMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if model.hardwarePrefs.lightingMode.usesSpeed {
                    Stepper("Speed: \(model.hardwarePrefs.lightingSpeed)", value: $model.hardwarePrefs.lightingSpeed, in: 1...3)
                }
                if model.hardwarePrefs.lightingMode.usesBrightness {
                    Stepper("Brightness: \(model.hardwarePrefs.lightingBrightness)", value: $model.hardwarePrefs.lightingBrightness, in: 1...4)
                }
                Button("Apply Lighting") {
                    let p = model.hardwarePrefs
                    model.runHardware("Setting lighting") {
                        try await $0.setLighting(mode: p.lightingMode, brightness: p.lightingBrightness, speed: p.lightingSpeed)
                    }
                }
            }

            Section("Power") {
                Stepper("Sleep after \(model.hardwarePrefs.sleepMinutes) min idle", value: $model.hardwarePrefs.sleepMinutes, in: 1...15)
                Toggle("Wake on movement", isOn: $model.hardwarePrefs.moveWakeup)
                Button("Apply Power Settings") {
                    let p = model.hardwarePrefs
                    model.runHardware("Setting power") {
                        try await $0.setPower(sleepMinutes: p.sleepMinutes, moveWakeup: p.moveWakeup, moveLighting: false)
                    }
                }
            }

            Section {
                Button("Factory Reset Mouse…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .disabled(model.hardwareBusy)
        .onAppear(perform: loadDPI)
        .onChange(of: model.hardwareStatus?.sensorType) { loadDPI() }
        .confirmationDialog("Reset all onboard settings to factory defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                model.hardwarePrefs = HardwarePrefs()
                model.runHardware("Factory reset") { try await $0.factoryReset() }
                loadDPI()
            }
        }
    }

    private var maxDPI: Int {
        model.hardwareStatus?.defaultDPILevels.max() ?? 6400
    }

    private func loadDPI() {
        dpiLevels = model.hardwarePrefs.dpiLevels ?? model.hardwareStatus?.defaultDPILevels ?? [400, 800, 1200, 1600, 2400, 3200, 6400]
        activeLevel = min(Int(model.hardwareStatus?.dpiLevel ?? 0), dpiLevels.count - 1)
    }
}

private struct DPILevelRow: View {
    let index: Int
    @Binding var dpi: Int
    @Binding var activeLevel: Int
    let maxDPI: Int
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack {
            Button { activeLevel = index } label: {
                Image(systemName: activeLevel == index ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.borderless)
            .help("Make this the active level")
            Text("Level \(index + 1)")
            Slider(value: sliderValue, in: 100...Double(maxDPI), step: 100)
            Text("\(dpi)").monospacedDigit().frame(width: 50, alignment: .trailing)
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(dpi) }, set: { dpi = Int($0 / 100) * 100 })
    }
}
