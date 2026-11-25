import MR5Protocol
import SwiftUI

@main
struct EdifierBarApp: App {
    @State private var speaker = SpeakerController()

    init() {
        setvbuf(stdout, nil, _IOLBF, 0)
        Snapshot.runIfRequested()
    }  // line-buffered debug log when launched via `open --stdout`

    var body: some Scene {
        MenuBarExtra {
            PanelView(speaker: speaker)
        } label: {
            Image(systemName: speaker.status == .connected ? "hifispeaker.2.fill" : "hifispeaker.2")
        }
        .menuBarExtraStyle(.window)
    }
}

struct PanelView: View {
    @Bindable var speaker: SpeakerController
    /// false for offline snapshots (a ScrollView has no intrinsic height to render).
    var scrollable = true
    @State private var contentHeight: CGFloat = 600

    /// Keep the panel on screen: never taller than the visible screen area.
    private var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 800) - 40 }

    var body: some View {
        if scrollable {
            ScrollView(.vertical) {
                content.background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            }
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
            .frame(width: 440, height: min(contentHeight, maxHeight))
        } else {
            content
        }
    }

    private var lang: AppLanguage { speaker.language }
    private func t(_ en: String, _ hu: String) -> String { lang == .english ? en : hu }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if speaker.status == .connected {
                Divider()
                volumeSection
                if let tuning = speaker.tuning {
                    Divider()
                    tuningSection(tuning)
                }
                if speaker.channel != nil {
                    Divider()
                    channelSection
                }
                if speaker.codec != nil {
                    Divider()
                    CodecSection(speaker: speaker)
                }
                if !speaker.devices.isEmpty {
                    Divider()
                    DevicesSection(speaker: speaker)
                }
            }
            if let e = speaker.lastError {
                Text(e(lang)).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(18)
        .frame(width: 440)
    }

    private var header: some View {
        HStack {
            Image(systemName: "hifispeaker.2.fill").font(.title2)
            VStack(alignment: .leading) {
                Text(speaker.deviceName ?? "Edifier MR5").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if speaker.status == .connected {
                Button { speaker.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(t("Reload state", "Állapot újraolvasása"))
            }
        }
    }

    private var statusText: String {
        switch speaker.status {
        case .connected: t("Connected (BLE)", "Csatlakozva (BLE)")
        case .connecting: t("Connecting…", "Csatlakozás…")
        case .scanning: t("Searching… (close ConneX on the phone)", "Keresés… (zárd be a ConneX-et a telefonon)")
        case .idle: speaker.autoConnect ? t("Waiting…", "Várakozás…") : t("Disconnected", "Leválasztva")
        case .bluetoothOff: t("Bluetooth is off", "A Bluetooth ki van kapcsolva")
        case .unauthorized: t("No Bluetooth permission (System Settings › Privacy)",
                              "Nincs Bluetooth-engedély (Rendszerbeállítások › Adatvédelem)")
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("Volume", "Hangerő"))
                HelpButton(text: Help.volume, lang: lang)
                Spacer()
                Text(speaker.volume.map(String.init) ?? "–").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(speaker.volume ?? 0) },
                    set: { speaker.setVolume(Int($0.rounded())) }
                ), in: 0...Double(speaker.maxVolume), step: 1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            .disabled(speaker.volume == nil)
        }
    }

    @ViewBuilder
    private func tuningSection(_ tuning: MR5.Tuning) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t("Sound mode", "Hangzásmód")).font(.subheadline.bold())
                HelpButton(text: Help.soundMode, lang: lang)
            }
            Picker("", selection: Binding(
                get: { tuning.mode ?? .music },
                set: { m in speaker.update { $0.mode = m } }
            )) {
                Text("Monitor").tag(MR5.SoundMode.monitor)
                Text("Music").tag(MR5.SoundMode.music)
                Text("Custom").tag(MR5.SoundMode.custom)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)

            if tuning.mode == .custom, speaker.eq != nil {
                CustomEQSection(speaker: speaker)
            }

            LowCutRow(hz: tuning.lowCutHz, lang: lang) { hz in speaker.update { $0.lowCutHz = hz } }

            labeledPicker(t("Slope", "Meredekség"), help: Help.slope, selection: Binding(
                get: { tuning.slopeIndex },
                set: { i in speaker.update { $0.slopeIndex = i } }
            ), values: Array(MR5.Tuning.slopes.indices)) { "\(MR5.Tuning.slopes[$0]) " + t("dB/oct", "dB/okt") }

            labeledPicker(t("Acoustic space", "Akusztikus tér"), help: Help.acousticSpace, selection: Binding(
                get: { tuning.acousticSpaceIndex },
                set: { i in speaker.update { $0.acousticSpaceIndex = i } }
            ), values: Array(MR5.Tuning.acousticSpaces.indices)) { "\(MR5.Tuning.acousticSpaces[$0]) dB" }

            HStack {
                Text(t("Desktop Control", "Asztali mód (Desktop Control)"))
                HelpButton(text: Help.desktopControl, lang: lang)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { tuning.desktopControl },
                    set: { on in speaker.update { $0.desktopControl = on } }
                ))
                .toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private func labeledPicker<V: Hashable>(_ title: String, help: Text2, selection: Binding<V>, values: [V],
                                            label: @escaping (V) -> String) -> some View {
        HStack {
            Text(title)
            HelpButton(text: help, lang: lang)
            Spacer()
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { Text(label($0)).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
    }

    private var channelSection: some View {
        HStack {
            Text(t("Active speaker", "Aktív hangfal"))
            HelpButton(text: Help.channel, lang: lang)
            Spacer()
            Picker("", selection: Binding(
                get: { speaker.channel ?? .right },
                set: { speaker.setChannel($0) }
            )) {
                Text(t("Left", "Bal")).tag(MR5.Channel.left)
                Text(t("Right", "Jobb")).tag(MR5.Channel.right)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(t("Auto-connect", "Automatikus csatlakozás"), isOn: $speaker.autoConnect)
                    .toggleStyle(.switch).controlSize(.mini)
                HelpButton(text: Help.autoConnect, lang: lang)
                Spacer()
                Picker("", selection: $speaker.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize().controlSize(.small)
            }
            HStack {
                Spacer()
                Button(t("Quit", "Kilépés")) { NSApp.terminate(nil) }
            }
        }
        .font(.caption)
    }
}

/// Low cutoff frequency: 20–100 Hz slider with −/+ steps and reset to 30 Hz.
/// The speaker is written only when dragging ends (or on a button press).
struct LowCutRow: View {
    let hz: Int
    let lang: AppLanguage
    let commit: (Int) -> Void
    @State private var draft: Double?

    private var range: ClosedRange<Int> { MR5.Tuning.lowCutRange }
    private var shown: Int { draft.map { Int($0.rounded()) } ?? hz }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lang == .english ? "Low cutoff" : "Mélyvágás")
                HelpButton(text: Help.lowCut, lang: lang)
                Spacer()
                Text("\(shown) Hz").monospacedDigit().foregroundStyle(.secondary)
                Button { commit(MR5.Tuning.lowCutDefault) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help(lang == .english ? "Reset to 30 Hz" : "Vissza 30 Hz-re")
                    .disabled(hz == MR5.Tuning.lowCutDefault)
            }
            HStack {
                Button { step(-1) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).disabled(hz <= range.lowerBound)
                Slider(value: Binding(get: { draft ?? Double(hz) }, set: { draft = $0 }),
                       in: Double(range.lowerBound)...Double(range.upperBound),
                       step: Double(MR5.Tuning.lowCutStep)) { editing in
                    if !editing, let d = draft {
                        draft = nil
                        let v = Int(d.rounded())
                        if v != hz { commit(v) }
                    }
                }
                Button { step(1) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless).disabled(hz >= range.upperBound)
            }
        }
    }

    private func step(_ dir: Int) {
        let v = min(max(hz + dir * MR5.Tuning.lowCutStep, range.lowerBound), range.upperBound)
        if v != hz { commit(v) }
    }
}

/// LDAC codec selection. Changing it makes the speaker reconnect, so ask first.
struct CodecSection: View {
    let speaker: SpeakerController
    @State private var pending: MR5.Codec?

    private var lang: AppLanguage { speaker.language }
    private func t(_ en: String, _ hu: String) -> String { lang == .english ? en : hu }

    private func title(_ c: MR5.Codec) -> String {
        switch c {
        case .ldac96k: t("LDAC 96 kHz — best quality", "LDAC 96 kHz – legjobb minőség")
        case .ldac48k: t("LDAC 44.1/48 kHz — balanced", "LDAC 44,1/48 kHz – kiegyensúlyozott")
        case .ldacOff: t("LDAC off — default codec", "LDAC ki – alapértelmezett kodek")
        }
    }

    var body: some View {
        HStack {
            Text(t("HD audio codec", "HD audiokodek"))
            HelpButton(text: Help.codec, lang: lang)
            Spacer()
            Picker("", selection: Binding(
                get: { speaker.codec ?? .ldac48k },
                set: { if $0 != speaker.codec { pending = $0 } }
            )) {
                ForEach([MR5.Codec.ldac96k, .ldac48k, .ldacOff], id: \.self) { Text(title($0)).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        .confirmationDialog(t("The speaker will reconnect", "A hangfal újracsatlakozik"),
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(t("Change codec", "Kodek váltása")) {
                if let c = pending { speaker.setCodec(c) }
                pending = nil
            }
            Button(t("Cancel", "Mégse"), role: .cancel) { pending = nil }
        } message: {
            Text(t("Audio stops for a few seconds while the speaker reconnects to its devices.",
                   "A hang néhány másodpercre megszakad, amíg a hangfal újracsatlakozik az eszközeihez."))
        }
    }
}

/// Paired source devices: switch each one on (connect) or off (disconnect).
struct DevicesSection: View {
    let speaker: SpeakerController

    private var lang: AppLanguage { speaker.language }
    private func t(_ en: String, _ hu: String) -> String { lang == .english ? en : hu }

    var body: some View {
        let connectedCount = speaker.devices.filter(\.connected).count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Bluetooth devices", "Bluetooth-eszközök")).font(.subheadline.bold())
                HelpButton(text: Help.devices, lang: lang)
                Spacer()
                Text("\(connectedCount)/\(speaker.maxDevices)").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(speaker.devices, id: \.self) { d in
                HStack {
                    Image(systemName: d.connected ? "link" : "link.badge.plus")
                        .foregroundStyle(d.connected ? .primary : .secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.name).lineLimit(1)
                        if d.addressString == speaker.hostAddress {
                            Text(t("this Mac", "ez a Mac")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if speaker.busyDevice == d.addressString {
                        ProgressView().controlSize(.small)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { d.connected },
                            set: { speaker.setDevice(d, connected: $0) }
                        ))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .disabled(speaker.busyDevice != nil || (!d.connected && connectedCount >= speaker.maxDevices))
                        .help(!d.connected && connectedCount >= speaker.maxDevices
                              ? t("Disconnect another device first (max. \(speaker.maxDevices)).",
                                  "Előbb válassz le egy másik eszközt (max. \(speaker.maxDevices)).")
                              : "")
                    }
                }
            }
        }
    }
}

/// Custom EQ editor: base (Monitor/Music), 9 bands −3…+3 dB, reset.
struct CustomEQSection: View {
    let speaker: SpeakerController
    @State private var draft: [Int: Double] = [:]
    @State private var confirmReset = false

    private var lang: AppLanguage { speaker.language }
    private func t(_ en: String, _ hu: String) -> String { lang == .english ? en : hu }

    private func freqLabel(_ hz: Int) -> String {
        hz >= 1000 ? "\(hz / 1000) kHz" : "\(hz) Hz"
    }

    private func dbLabel(_ db: Double) -> String {
        let s = db == db.rounded() ? String(format: "%+.0f", db) : String(format: "%+.1f", db)
        return (db == 0 ? "0" : s) + " dB"
    }

    var body: some View {
        if let eq = speaker.eq {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(t("Custom EQ", "Egyéni EQ")).font(.subheadline.bold())
                    HelpButton(text: Help.eqGain, lang: lang)
                    Spacer()
                    Button { confirmReset = true } label: {
                        Label(t("Reset", "Visszaállítás"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless).font(.caption)
                    HelpButton(text: Help.eqReset, lang: lang)
                }
                HStack {
                    Text(t("Base", "Alap"))
                    HelpButton(text: Help.eqBase, lang: lang)
                    Spacer()
                    Picker("", selection: Binding(get: { eq.base }, set: { speaker.setEQBase($0) })) {
                        Text("Monitor").tag(MR5.EQBase.monitor)
                        Text("Music").tag(MR5.EQBase.music)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                ForEach(eq.bands, id: \.index) { band in
                    let value = draft[band.index] ?? Double(band.step)
                    HStack(spacing: 10) {
                        Text(freqLabel(band.frequency))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: Binding(get: { value }, set: { draft[band.index] = $0 }),
                               in: 0...Double(eq.maxStep), step: 1) { editing in
                            if !editing, let d = draft[band.index] {
                                draft[band.index] = nil
                                let step = Int(d.rounded())
                                if step != band.step { speaker.setEQBand(band.index, step: step) }
                            }
                        }
                        .controlSize(.small)
                        Text(dbLabel(eq.gainDB(Int(value.rounded()))))
                            .font(.caption).monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            .confirmationDialog(t("Reset the custom EQ?", "Visszaállítod az egyéni EQ-t?"), isPresented: $confirmReset) {
                Button(t("Reset", "Visszaállítás"), role: .destructive) { speaker.resetEQ() }
                Button(t("Cancel", "Mégse"), role: .cancel) {}
            } message: {
                Text(Help.eqReset(lang))
            }
        }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
