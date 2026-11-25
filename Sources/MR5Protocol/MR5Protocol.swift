// Edifier MR5 BLE frame format and the commands observed in the ConneX capture.
// See PROTOCOL.md. Do not add commands here that were not observed in a capture.

import Foundation

public enum MR5 {
    /// 16-bit service UUID advertised by the speaker ("EDIFIER BLE").
    public static let advertisedService = "3A01"
    /// Bluetooth SIG company id in the manufacturer data (little-endian E0 07).
    public static let manufacturerID: UInt16 = 0x07E0

    public enum Command: UInt8, Sendable {
        // queries (empty payload)
        case name = 0xC9
        case tuning = 0xD5
        case volume = 0x66
        case channel = 0xBB
        case devices = 0xAD
        case codec = 0x91
        case customEQ = 0x43
        // writes
        case setTuning = 0xC4
        case setVolume = 0x67
        case setChannel = 0xBC
        case connectDevice = 0xAE
        case disconnectDevice = 0xAF
        case setCodec = 0x92
        case setEQBand = 0x44
        case resetEQ = 0x45     // empty request; reply carries the flat EQ
    }

    /// Commands the app may write, with payload validation. Queries have empty payloads.
    public static func request(_ cmd: Command, _ payload: [UInt8] = []) -> Data {
        var f: [UInt8] = [0xAA, 0xEC, cmd.rawValue, 0x00, UInt8(payload.count)] + payload
        f.append(checksum(f))
        return Data(f)
    }

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }

    // MARK: typed builders (values restricted to what was observed)

    public static func setVolume(_ v: Int, max: Int = 30) -> Data? {
        guard (0...min(max, 30)).contains(v) else { return nil }
        return request(.setVolume, [UInt8(v)])
    }

    public static func setTuning(_ t: Tuning) -> Data? {
        guard t.isAllowed else { return nil }
        return request(.setTuning, t.bytes)
    }

    public static func setChannel(prefix: UInt8, _ ch: Channel) -> Data? {
        guard prefix == 0x04 else { return nil }  // only 04 was observed
        return request(.setChannel, [prefix, ch.rawValue])
    }

    public static func connect(_ d: PairedDevice) -> Data? {
        d.address.count == 6 ? request(.connectDevice, d.address) : nil
    }

    public static func disconnect(_ d: PairedDevice) -> Data? {
        d.address.count == 6 ? request(.disconnectDevice, d.address) : nil
    }

    public static func setCodec(prefix: UInt8, _ c: Codec) -> Data? {
        guard prefix == 0x0F else { return nil }  // only 0F was observed
        return request(.setCodec, [prefix, c.rawValue, 0xFF])
    }

    /// Custom EQ band write: `<base> <band> <freq hi> <freq lo> <gain step>`.
    public static func setEQBand(base: EQBase, band: EQBand, step: Int, maxStep: Int = 12) -> Data? {
        guard (0...maxStep).contains(step), maxStep == 12, (0..<9).contains(band.index) else { return nil }
        return request(.setEQBand, [base.rawValue, UInt8(band.index), UInt8(band.frequency >> 8),
                                    UInt8(band.frequency & 0xFF), UInt8(step)])
    }

    // MARK: replies

    public struct Frame: Equatable, Sendable {
        public let command: UInt8
        public let payload: [UInt8]
        public init(command: UInt8, payload: [UInt8]) {
            self.command = command
            self.payload = payload
        }
    }

    /// Incremental parser for `BB EC cmd 00 len payload sum` frames. Feeds may
    /// contain several frames or partial frames.
    public struct Parser: Sendable {
        private var buf: [UInt8] = []
        public init() {}

        public mutating func feed(_ data: Data) -> [Frame] {
            buf.append(contentsOf: data)
            var out: [Frame] = []
            while true {
                // resync to header
                while buf.count >= 2, !(buf[0] == 0xBB && buf[1] == 0xEC) { buf.removeFirst() }
                guard buf.count >= 6 else { break }
                let len = Int(buf[3]) << 8 | Int(buf[4])
                guard len <= 512 else { buf.removeFirst(); continue }
                let total = 5 + len + 1
                guard buf.count >= total else { break }
                let frame = Array(buf[0..<total])
                if checksum(frame.dropLast()) == frame[total - 1] {
                    out.append(Frame(command: frame[2], payload: Array(frame[5..<(5 + len)])))
                    buf.removeFirst(total)
                } else {
                    buf.removeFirst()
                }
            }
            return out
        }
    }

    // MARK: models

    public enum SoundMode: UInt8, CaseIterable, Sendable {
        case monitor = 0, music = 1, custom = 2
    }

    public enum Channel: UInt8, CaseIterable, Sendable {
        case right = 1, left = 2
    }

    /// LDAC setting (0x91 / 0x92). Changing it makes the speaker drop and re-establish its links.
    public enum Codec: UInt8, CaseIterable, Sendable {
        case ldacOff = 0, ldac48k = 1, ldac96k = 2
    }

    /// Base sound under the custom EQ ("Mode Selection" in ConneX).
    public enum EQBase: UInt8, CaseIterable, Sendable {
        case monitor = 0, music = 1
    }

    public struct EQBand: Equatable, Hashable, Sendable {
        public let index: Int
        public let frequency: Int   // Hz
        public var step: Int        // 0...maxStep, center = 0 dB
    }

    /// Custom EQ state. Gain step 0...12, 6 = 0 dB, 0.5 dB per step (−3…+3 dB).
    public struct CustomEQ: Equatable, Sendable {
        public var maxStep: Int
        public var base: EQBase
        public var bands: [EQBand]

        public var centerStep: Int { maxStep / 2 }
        public func gainDB(_ step: Int) -> Double { Double(step - centerStep) * 0.5 }

        /// 0x43 reply: `<maxStep> <count> <base> {<idx> <freq16 BE> <step>}×count [<id ×4> <name>]`.
        public init?(query p: [UInt8]) {
            guard p.count >= 3, let base = EQBase(rawValue: p[2]) else { return nil }
            guard let bands = Self.bands(p, from: 3, count: Int(p[1])) else { return nil }
            self.init(maxStep: Int(p[0]), base: base, bands: bands)
        }

        /// 0x45 (reset) reply: `<base> {<idx> <freq16 BE> <step>}×9`.
        public init?(reset p: [UInt8], maxStep: Int = 12) {
            guard p.count >= 1, let base = EQBase(rawValue: p[0]),
                  let bands = Self.bands(p, from: 1, count: (p.count - 1) / 4) else { return nil }
            self.init(maxStep: maxStep, base: base, bands: bands)
        }

        public init(maxStep: Int, base: EQBase, bands: [EQBand]) {
            self.maxStep = maxStep; self.base = base; self.bands = bands
        }

        private static func bands(_ p: [UInt8], from start: Int, count: Int) -> [EQBand]? {
            guard count > 0, p.count >= start + count * 4 else { return nil }
            return (0..<count).map { i in
                let o = start + i * 4
                return EQBand(index: Int(p[o]), frequency: Int(p[o + 1]) << 8 | Int(p[o + 2]), step: Int(p[o + 3]))
            }
        }
    }

    public struct PairedDevice: Equatable, Hashable, Sendable {
        public let name: String
        /// 6 bytes as sent on the wire (little-endian BD_ADDR).
        public let address: [UInt8]
        public let connected: Bool
        /// Human-readable "AA:BB:CC:DD:EE:FF".
        public var addressString: String {
            address.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
        }
    }

    /// Decodes the 0xAD reply: `<max> <connectedCount> { <len> <name> <addr6> }*`.
    /// The first `connectedCount` entries are the connected devices.
    public static func parseDevices(_ p: [UInt8]) -> (max: Int, devices: [PairedDevice])? {
        guard p.count >= 2 else { return nil }
        let max = Int(p[0]), connected = Int(p[1])
        var out: [PairedDevice] = []
        var i = 2
        while i < p.count {
            let len = Int(p[i])
            guard len >= 6, i + 1 + len <= p.count else { return nil }
            let entry = Array(p[(i + 1)...(i + len)])
            let name = String(decoding: entry.dropLast(6), as: UTF8.self)
            out.append(PairedDevice(name: name, address: Array(entry.suffix(6)), connected: out.count < connected))
            i += 1 + len
        }
        return (max, out)
    }

    public struct Tuning: Equatable, Sendable {
        public var bytes: [UInt8]   // exactly 7, as read from the speaker

        /// Low cutoff range and default as shown in ConneX (20–100 Hz slider, reset = 30 Hz).
        /// 30/40/50 Hz were captured; the rest of the range was confirmed by the user from the ConneX UI.
        public static let lowCutRange = 20...100
        public static let lowCutStep = 10
        public static let lowCutDefault = 30
        public static let slopes = [-6, -12, -18, -24]          // index = wire value
        public static let acousticSpaces = [0, -1, -2, -3, -4]   // index = wire value

        public init?(_ payload: [UInt8]) {
            guard payload.count == 7 else { return nil }
            bytes = payload
        }

        public var mode: SoundMode? {
            get { SoundMode(rawValue: bytes[0]) }
            set { if let v = newValue { bytes[0] = v.rawValue } }
        }
        public var lowCutHz: Int {
            get { Int(bytes[2]) << 8 | Int(bytes[3]) }
            set { bytes[2] = UInt8((newValue >> 8) & 0xFF); bytes[3] = UInt8(newValue & 0xFF) }
        }
        public var slopeIndex: Int {
            get { Int(bytes[4]) }
            set { bytes[4] = UInt8(newValue) }
        }
        public var acousticSpaceIndex: Int {
            get { Int(bytes[5]) }
            set { bytes[5] = UInt8(newValue) }
        }
        public var desktopControl: Bool {
            get { bytes[6] == 1 }
            set { bytes[6] = newValue ? 1 : 0 }
        }

        /// Only allow writing states whose fields are inside the ranges ConneX offers.
        public var isAllowed: Bool {
            bytes.count == 7
                && mode != nil
                && bytes[1] == 0x02
                && Self.lowCutRange.contains(lowCutHz)
                && (0..<Self.slopes.count).contains(slopeIndex)
                && (0..<Self.acousticSpaces.count).contains(acousticSpaceIndex)
                && bytes[6] <= 1
        }
    }
}
