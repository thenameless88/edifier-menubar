import Foundation
import MR5Protocol

nonisolated(unsafe) var failures = 0
func expect(_ ok: Bool, _ line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line)") }
}

private func hex(_ s: String) -> Data {
    Data(s.split(separator: " ").map { UInt8($0, radix: 16)! })
}

// Every expected frame below is copied verbatim from the ConneX capture.
func devicesAndCodecMatchCapture() {
    expect(MR5.request(.devices) == hex("aa ec ad 00 00 43"))
    expect(MR5.request(.codec) == hex("aa ec 91 00 00 27"))
    expect(MR5.setCodec(prefix: 0x0F, .ldac96k) == hex("aa ec 92 00 03 0f 02 ff 3b"))
    expect(MR5.setCodec(prefix: 0x0F, .ldacOff) == hex("aa ec 92 00 03 0f 00 ff 39"))
    expect(MR5.setCodec(prefix: 0x0F, .ldac48k) == hex("aa ec 92 00 03 0f 01 ff 3a"))
    expect(MR5.setCodec(prefix: 0x0E, .ldac48k) == nil)

    // Device names/addresses are test-device placeholders (see PROTOCOL.md); layout as captured.
    let reply = [UInt8](hex("02 01 10 54 65 73 74 20 50 68 6f 6e 65 0b 00 00 00 00 02 10 54 65 73 74 20 4d 61 63 20 42 0c 00 00 00 00 02 10 54 65 73 74 20 4d 61 63 20 41 0a 00 00 00 00 02"))
    guard let (max, devs) = MR5.parseDevices(reply) else { expect(false); return }
    expect(max == 2 && devs.count == 3)
    expect(devs.map(\.name) == ["Test Phone", "Test Mac B", "Test Mac A"])
    expect(devs.map(\.connected) == [true, false, false])
    expect(devs[2].addressString == "02:00:00:00:00:0A")
    expect(MR5.disconnect(devs[2]) == hex("aa ec af 00 06 0a 00 00 00 00 02 57"))
    expect(MR5.disconnect(devs[1]) == hex("aa ec af 00 06 0c 00 00 00 00 02 59"))
    expect(MR5.connect(devs[2]) == hex("aa ec ae 00 06 0a 00 00 00 00 02 56"))
}

func queriesMatchCapture() {
    expect(MR5.request(.name) == hex("aa ec c9 00 00 5f"))
    expect(MR5.request(.tuning) == hex("aa ec d5 00 00 6b"))
    expect(MR5.request(.volume) == hex("aa ec 66 00 00 fc"))
    expect(MR5.request(.channel) == hex("aa ec bb 00 00 51"))
}

func writesMatchCapture() {
    expect(MR5.setVolume(20) == hex("aa ec 67 00 01 14 12"))
    expect(MR5.setVolume(14) == hex("aa ec 67 00 01 0e 0c"))
    expect(MR5.setVolume(31) == nil)
    expect(MR5.setChannel(prefix: 4, .left) == hex("aa ec bc 00 02 04 02 5a"))
    expect(MR5.setChannel(prefix: 4, .right) == hex("aa ec bc 00 02 04 01 59"))
    expect(MR5.setChannel(prefix: 5, .right) == nil)

    var t = MR5.Tuning([0x01, 0x02, 0x00, 0x1E, 0x03, 0x00, 0x00])!
    t.mode = .monitor
    expect(MR5.setTuning(t) == hex("aa ec c4 00 07 00 02 00 1e 03 00 00 84"))
    t.mode = .music; t.lowCutHz = 50
    expect(MR5.setTuning(t) == hex("aa ec c4 00 07 01 02 00 32 03 00 00 99"))
    t.lowCutHz = 30; t.slopeIndex = 0
    expect(MR5.setTuning(t) == hex("aa ec c4 00 07 01 02 00 1e 00 00 00 82"))
    t.slopeIndex = 3; t.acousticSpaceIndex = 4
    expect(MR5.setTuning(t) == hex("aa ec c4 00 07 01 02 00 1e 03 04 00 89"))
    t.acousticSpaceIndex = 0; t.desktopControl = true
    expect(MR5.setTuning(t) == hex("aa ec c4 00 07 01 02 00 1e 03 00 01 86"))
    t.lowCutHz = 110
    expect(MR5.setTuning(t) == nil)
    t.lowCutHz = 10
    expect(MR5.setTuning(t) == nil)
    t.lowCutHz = 100
    expect(MR5.setTuning(t) != nil)
}

func parserHandlesSplitAndJoinedFrames() {
    var p = MR5.Parser()
    let a = hex("bb ec 67 00 01 01 10 bb ec 66 00 02 1e 14")
    let b = hex("41 bb ec c9 00 0b 45 44 49 46 49 45 52 20 4d 52 35 67")
    expect(p.feed(a) == [MR5.Frame(command: 0x67, payload: [1])])
    let rest = p.feed(b)
    expect(rest.count == 2)
    expect(rest[0] == MR5.Frame(command: 0x66, payload: [0x1E, 0x14]))
    expect(String(decoding: rest[1].payload, as: UTF8.self) == "EDIFIER MR5")
}

func parserRejectsBadChecksum() {
    var p = MR5.Parser()
    expect(p.feed(hex("bb ec 67 00 01 01 11")).isEmpty)
}

func customEQMatchesCapture() {
    expect(MR5.request(.customEQ) == hex("aa ec 43 00 00 d9"))
    expect(MR5.request(.resetEQ) == hex("aa ec 45 00 00 db"))
    let q = [UInt8](hex("0c 09 00 00 00 3e 06 01 00 7d 0a 02 00 fa 0c 03 01 f4 06 04 03 e8 06 05 07 d0 06 06 0f a0 06 07 1f 40 06 08 3e 80 06 e4 b0 06 6b 53 6f 75 6e 64 20 45 66 66 65 63 74 73"))
    guard let eq = MR5.CustomEQ(query: q) else { expect(false); return }
    expect(eq.maxStep == 12 && eq.base == .monitor && eq.bands.count == 9)
    expect(eq.bands.map(\.frequency) == [62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
    expect(eq.bands[1].step == 10 && eq.gainDB(10) == 2.0 && eq.gainDB(0) == -3.0)
    expect(MR5.setEQBand(base: .monitor, band: eq.bands[0], step: 8) == hex("aa ec 44 00 05 00 00 00 3e 08 25"))
    expect(MR5.setEQBand(base: .monitor, band: eq.bands[8], step: 0) == hex("aa ec 44 00 05 00 08 3e 80 00 a5"))
    expect(MR5.setEQBand(base: .music, band: eq.bands[2], step: 12) == hex("aa ec 44 00 05 01 02 00 fa 0c e8"))
    expect(MR5.setEQBand(base: .music, band: eq.bands[0], step: 6) == hex("aa ec 44 00 05 01 00 00 3e 06 24"))
    expect(MR5.setEQBand(base: .monitor, band: eq.bands[0], step: 13) == nil)
    let r = [UInt8](hex("00 00 00 3e 06 01 00 7d 06 02 00 fa 06 03 01 f4 06 04 03 e8 06 05 07 d0 06 06 0f a0 06 07 1f 40 06 08 3e 80 06"))
    let flat = MR5.CustomEQ(reset: r)
    expect(flat?.bands.count == 9 && flat?.bands.allSatisfy { $0.step == 6 } == true && flat?.base == .monitor)
}

queriesMatchCapture()
devicesAndCodecMatchCapture()
customEQMatchesCapture()
writesMatchCapture()
parserHandlesSplitAndJoinedFrames()
parserRejectsBadChecksum()
print(failures == 0 ? "all protocol checks passed" : "\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
