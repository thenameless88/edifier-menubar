// BLE discovery: scans for Edifier devices, connects, dumps GATT services/characteristics.
// Usage: swift tools/blescan.swift [nameFilter] [seconds]
import CoreBluetooth
import Foundation

let filter = (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "edifier").lowercased()
let seconds = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 15 : 15

final class Scanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var seen = Set<UUID>()
    var targets: [CBPeripheral] = []
    var pending = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("state:", c.state.rawValue, "(5 = poweredOn)")
        guard c.state == .poweredOn else { return }
        // Already-connected peripherals with common services
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            c.stopScan()
            print("scan done, \(self.targets.count) match(es)")
            if self.targets.isEmpty { exit(0) }
            for p in self.targets { p.delegate = self; c.connect(p) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { print("timeout"); exit(0) }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        guard !seen.contains(p.identifier) else { return }
        seen.insert(p.identifier)
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? "?"
        let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data).map { $0.map { String(format: "%02x", $0) }.joined() } ?? ""
        let svcs = (ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let hit = name.lowercased().contains(filter) || name.lowercased().contains("mr5") || name.lowercased().contains("mr3")
        print("\(hit ? "**" : "  ") \(name) rssi=\(rssi) id=\(p.identifier) svcs=\(svcs) mfg=\(mfg)")
        if hit { targets.append(p) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("connected \(p.name ?? "?")")
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        print("connect failed:", error as Any)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            pending += 1
            p.discoverCharacteristics(nil, for: s)
        }
        if (p.services ?? []).isEmpty { print("no services", error as Any); exit(0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        print("service \(s.uuid.uuidString)")
        for ch in s.characteristics ?? [] {
            var props: [String] = []
            let pr = ch.properties
            if pr.contains(.read) { props.append("read") }
            if pr.contains(.write) { props.append("write") }
            if pr.contains(.writeWithoutResponse) { props.append("writeNoRsp") }
            if pr.contains(.notify) { props.append("notify") }
            if pr.contains(.indicate) { props.append("indicate") }
            print("   char \(ch.uuid.uuidString) [\(props.joined(separator: ","))]")
        }
        pending -= 1
        if pending == 0 { exit(0) }
    }
}

let s = Scanner()
RunLoop.main.run()
