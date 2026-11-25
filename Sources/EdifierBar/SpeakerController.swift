import CoreBluetooth
import IOBluetooth
import Foundation
import MR5Protocol
import Observation

/// Talks to the MR5 over BLE (see PROTOCOL.md). Runs on the main queue.
@MainActor
@Observable
final class SpeakerController: NSObject {
    enum Status: Equatable {
        case bluetoothOff, unauthorized, idle, scanning, connecting, connected
    }

    private(set) var status: Status = .idle { didSet { if status != oldValue { print("status", status) } } }
    private(set) var deviceName: String?
    private(set) var volume: Int?
    private(set) var maxVolume = 30
    private(set) var tuning: MR5.Tuning?
    private(set) var channel: MR5.Channel?
    private(set) var codec: MR5.Codec?
    private(set) var eq: MR5.CustomEQ?
    private(set) var devices: [MR5.PairedDevice] = []
    private(set) var maxDevices = 2
    /// Address of a device a connect/disconnect is in progress for.
    private(set) var busyDevice: String?
    /// This Mac's Bluetooth address, to mark it in the device list.
    private(set) var hostAddress: String? = IOBluetoothHostController.default()?.addressAsString()?
        .replacingOccurrences(of: "-", with: ":").uppercased()
    private(set) var lastError: Text2?
    var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .english {
        didSet { if !isPreview { UserDefaults.standard.set(language.rawValue, forKey: "language") } }
    }
    /// When false the app stays disconnected so ConneX on the phone can connect
    /// (the speaker accepts one LE central at a time).
    var autoConnect: Bool = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "autoConnect")
            autoConnect ? start() : disconnect()
        }
    }

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var isPreview = false
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var notifyChar: CBCharacteristic?
    @ObservationIgnored private var parser = MR5.Parser()
    @ObservationIgnored private var channelPrefix: UInt8?
    @ObservationIgnored private var codecPrefix: UInt8?
    @ObservationIgnored private var queue: [Data] = []
    @ObservationIgnored private var pendingVolume: Int?
    @ObservationIgnored private var volumeTimer: Timer?
    @ObservationIgnored private var retryTimer: Timer?

    private static let serviceUUID = CBUUID(string: MR5.advertisedService)
    private static let knownIDKey = "peripheralID"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func entry(_ name: String, _ last: UInt8) -> [UInt8] {
        [UInt8(name.utf8.count + 6)] + Array(name.utf8) + [last, 0, 0, 0, 0, 0x02]
    }

    /// Offline instance with sample state, used only for layout snapshots (no Bluetooth).
    init(preview language: AppLanguage) {
        super.init()
        isPreview = true
        hostAddress = "02:00:00:00:00:0A"
        self.language = language
        status = .connected
        deviceName = "EDIFIER MR5"
        volume = 18
        tuning = MR5.Tuning([0x01, 0x02, 0x00, 0x1E, 0x03, 0x00, 0x00])
        channel = .right
        channelPrefix = 0x04
        codec = .ldac48k
        codecPrefix = 0x0F
        tuning?.mode = .custom
        eq = MR5.CustomEQ(query: [UInt8](hex: "0c0900" + "00003e08" + "01007d0a" + "0200fa0c" + "0301f406" + "0403e806"
                                                      + "0507d005" + "060fa004" + "071f4006" + "083e8007"))
        devices = MR5.parseDevices([UInt8](hex: "0202") + entry("Test Mac A", 0x0A) + entry("Test Phone", 0x0B)
                                   + entry("Test Mac B", 0x0C))?.devices ?? []
    }

    // MARK: public actions

    func start() {
        guard autoConnect, let central, central.state == .poweredOn, peripheral == nil else { return }
        if let s = UserDefaults.standard.string(forKey: Self.knownIDKey), let id = UUID(uuidString: s),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
        } else {
            scan()
        }
    }

    func disconnect() {
        central.stopScan()
        retryTimer?.invalidate()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        reset(status: .idle)
    }

    func refresh() {
        send(MR5.request(.volume))
        send(MR5.request(.tuning))
        send(MR5.request(.channel))
        send(MR5.request(.codec))
        send(MR5.request(.devices))
        send(MR5.request(.customEQ))
    }

    /// Slider-friendly: coalesces rapid changes to ~8 writes/s.
    func setVolume(_ v: Int) {
        volume = v
        pendingVolume = v
        guard volumeTimer == nil else { return }
        flushVolume()
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                if self.pendingVolume == nil { t.invalidate(); self.volumeTimer = nil } else { self.flushVolume() }
            }
        }
    }

    func update(_ change: (inout MR5.Tuning) -> Void) {
        guard var t = tuning else { return }
        change(&t)
        guard let frame = MR5.setTuning(t) else { lastError = Text2("Value not seen in the capture; not sent.", "Nem megfigyelt érték, nem küldöm el."); return }
        tuning = t
        send(frame)
        send(MR5.request(.tuning))
    }

    func setChannel(_ ch: MR5.Channel) {
        guard let prefix = channelPrefix, let frame = MR5.setChannel(prefix: prefix, ch) else { return }
        channel = ch
        send(frame)
        send(MR5.request(.channel))
    }

    /// Changing the codec makes the speaker drop all links and reconnect (~10–20 s).
    func setCodec(_ c: MR5.Codec) {
        guard let prefix = codecPrefix, let frame = MR5.setCodec(prefix: prefix, c) else { return }
        codec = c
        send(frame)
    }

    func setEQBand(_ index: Int, step: Int) {
        guard var e = eq, let i = e.bands.firstIndex(where: { $0.index == index }),
              let frame = MR5.setEQBand(base: e.base, band: e.bands[i], step: step, maxStep: e.maxStep) else { return }
        e.bands[i].step = step
        eq = e
        send(frame)
        send(MR5.request(.customEQ))
    }

    /// ConneX switches the base by re-sending band 0 (current gain) with the new base byte.
    func setEQBase(_ base: MR5.EQBase) {
        guard var e = eq, let b0 = e.bands.first,
              let frame = MR5.setEQBand(base: base, band: b0, step: b0.step, maxStep: e.maxStep) else { return }
        e.base = base
        eq = e
        send(frame)
        send(MR5.request(.customEQ))
    }

    func resetEQ() {
        guard eq != nil else { return }
        send(MR5.request(.resetEQ))
    }

    func setDevice(_ d: MR5.PairedDevice, connected: Bool) {
        guard let frame = connected ? MR5.connect(d) : MR5.disconnect(d) else { return }
        busyDevice = d.addressString
        send(frame)
    }

    // MARK: internals

    private func flushVolume() {
        guard let v = pendingVolume, let frame = MR5.setVolume(v, max: maxVolume) else { pendingVolume = nil; return }
        pendingVolume = nil
        send(frame)
    }

    private func scan() {
        status = .scanning
        central.scanForPeripherals(withServices: nil)
    }

    private func connect(_ p: CBPeripheral) {
        central.stopScan()
        peripheral = p
        p.delegate = self
        status = .connecting
        central.connect(p)
    }

    private func reset(status s: Status) {
        peripheral = nil; writeChar = nil; notifyChar = nil
        queue.removeAll(); parser = MR5.Parser()
        deviceName = nil; volume = nil; tuning = nil; channel = nil; channelPrefix = nil
        codec = nil; codecPrefix = nil; devices = []; busyDevice = nil; eq = nil
        status = s
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        guard autoConnect else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private func send(_ data: Data) {
        queue.append(data)
        pump()
    }

    private func pump() {
        guard let p = peripheral, let c = writeChar else { return }
        while !queue.isEmpty, p.canSendWriteWithoutResponse {
            p.writeValue(queue.removeFirst(), for: c, type: .withoutResponse)
        }
    }

    private func handle(_ f: MR5.Frame) {
        print(String(format: "rx %02X", f.command), f.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
        switch f.command {
        case MR5.Command.name.rawValue:
            deviceName = String(decoding: f.payload, as: UTF8.self)
        case MR5.Command.volume.rawValue where f.payload.count == 2:
            maxVolume = Int(f.payload[0])
            if pendingVolume == nil && volumeTimer == nil { volume = Int(f.payload[1]) }
        case MR5.Command.tuning.rawValue:
            if let t = MR5.Tuning(f.payload) { tuning = t }
        case MR5.Command.channel.rawValue where f.payload.count == 2:
            channelPrefix = f.payload[0]
            channel = MR5.Channel(rawValue: f.payload[1])
        case MR5.Command.codec.rawValue where f.payload.count == 2,
             MR5.Command.setCodec.rawValue where f.payload.count == 2:
            codecPrefix = f.payload[0]
            codec = MR5.Codec(rawValue: f.payload[1])
        case MR5.Command.customEQ.rawValue:
            if let e = MR5.CustomEQ(query: f.payload) { eq = e }
        case MR5.Command.resetEQ.rawValue:
            if let e = MR5.CustomEQ(reset: f.payload, maxStep: eq?.maxStep ?? 12) { eq = e }
            send(MR5.request(.customEQ))
        case MR5.Command.devices.rawValue:
            if let (max, list) = MR5.parseDevices(f.payload) {
                maxDevices = max
                devices = list
                busyDevice = nil
            }
        case MR5.Command.connectDevice.rawValue, MR5.Command.disconnectDevice.rawValue:
            // 01 = done, 02 = in progress (a later 01 follows); the speaker then pushes a new 0xAD list
            if f.payload == [0x01] { send(MR5.request(.devices)) }
            else if f.payload != [0x02] { busyDevice = nil; lastError = Text2("The speaker refused the device change.", "A hangfal nem hajtotta végre az eszközváltást.") }
        case MR5.Command.setTuning.rawValue, MR5.Command.setVolume.rawValue, MR5.Command.setChannel.rawValue,
             MR5.Command.setEQBand.rawValue:
            if f.payload != [0x01] { lastError = Text2(String(format: "Speaker rejected command 0x%02X", f.command), String(format: "A hangfal elutasította (0x%02X)", f.command)) }
        default:
            break  // other notifications (status 0xC3 etc.) are ignored
        }
    }

    private static func isMR5(name: String?, ad: [String: Any]) -> Bool {
        if let svcs = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], svcs.contains(serviceUUID) { return true }
        if let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2, m[m.startIndex] == 0xE0, m[m.startIndex + 1] == 0x07 { return true }
        let n = (name ?? "").uppercased()
        return n == "EDIFIER BLE" || n.contains("MR5")
    }
}

extension SpeakerController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        MainActor.assumeIsolated {
            switch c.state {
            case .poweredOn: status = .idle; start()
            case .unauthorized: reset(status: .unauthorized)
            default: reset(status: .bluetoothOff)
            }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                                    advertisementData ad: [String: Any], rssi: NSNumber) {
        MainActor.assumeIsolated {
            let name = p.name ?? ad[CBAdvertisementDataLocalNameKey] as? String
            guard peripheral == nil, Self.isMR5(name: name, ad: ad) else { return }
            connect(p)
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        MainActor.assumeIsolated {
            UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.knownIDKey)
            p.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            lastError = error.map { Text2(verbatim: $0.localizedDescription) }
            reset(status: .idle)
            UserDefaults.standard.removeObject(forKey: Self.knownIDKey)
            scheduleRetry()
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard p == peripheral else { return }
            reset(status: .idle)
            scheduleRetry()
        }
    }
}

extension SpeakerController: CBPeripheralDelegate {
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let services = p.services ?? []
            // Prefer the advertised service; fall back to everything.
            let preferred = services.filter { $0.uuid == Self.serviceUUID }
            for s in preferred.isEmpty ? services : preferred { p.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for ch in s.characteristics ?? [] {
                if writeChar == nil, ch.properties.contains(.writeWithoutResponse) { writeChar = ch }
                if notifyChar == nil, ch.properties.contains(.notify) {
                    notifyChar = ch
                    p.setNotifyValue(true, for: ch)
                }
            }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard ch == notifyChar, ch.isNotifying, writeChar != nil else {
                if let error { lastError = Text2(verbatim: error.localizedDescription) }
                return
            }
            status = .connected
            lastError = nil
            send(MR5.request(.name))
            refresh()
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let v = ch.value else { return }
            for f in parser.feed(v) { handle(f) }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        MainActor.assumeIsolated { pump() }
    }
}
