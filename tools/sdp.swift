// Classic Bluetooth SDP dump. Usage: sdp <address>   (e.g. C8-24-78-AB-CD-EF)
import Foundation
import IOBluetooth

final class Q: NSObject {
    let dev: IOBluetoothDevice
    init(_ d: IOBluetoothDevice) { dev = d }
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        print("SDP status \(status), \(device.services?.count ?? 0) records for \(device.name ?? "?")")
        for case let rec as IOBluetoothSDPServiceRecord in device.services ?? [] {
            var ch: BluetoothRFCOMMChannelID = 0
            let rf = rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess ? " RFCOMM ch=\(ch)" : ""
            var psm: BluetoothL2CAPPSM = 0
            let l2 = rec.getL2CAPPSM(&psm) == kIOReturnSuccess ? " L2CAP psm=\(psm)" : ""
            var uuids: [String] = []
            if let list = rec.getAttributeDataElement(1)?.getArrayValue() {
                for case let e as IOBluetoothSDPDataElement in list {
                    if let u = e.getUUIDValue() { uuids.append(u.description) }
                }
            }
            print("- \(rec.getServiceName() ?? "(no name)")\(rf)\(l2) classes=\(uuids)")
            if status != -1, let attrs = rec.attributes as? [NSNumber: IOBluetoothSDPDataElement] {
                for (k, v) in attrs.sorted(by: { $0.key.intValue < $1.key.intValue }) where [1, 4, 9].contains(k.intValue) {
                    print("    attr 0x\(String(k.intValue, radix: 16)): \(v.description.replacingOccurrences(of: "\n", with: " "))")
                }
            }
        }
        if status != -1 { exit(0) }
    }
}

guard CommandLine.arguments.count > 1 else { print("usage: sdp <address>"); exit(1) }
let addr = CommandLine.arguments[1]
guard let d = IOBluetoothDevice(addressString: addr) else { print("bad address"); exit(1) }
let q = Q(d)
print("cached records:"); q.sdpQueryComplete(d, status: -1)
print("querying \(d.name ?? "?") \(addr) ...")
let r = d.performSDPQuery(q)
print("performSDPQuery ->", r)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("timeout"); exit(2) }
RunLoop.main.run()
