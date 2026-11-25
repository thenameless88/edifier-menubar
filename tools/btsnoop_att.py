#!/usr/bin/env python3
"""Dump BLE ATT traffic for one LE peer from an Android btsnoop_hci.log.

Usage: python3 -I tools/btsnoop_att.py btsnoop_hci.log <speaker LE address, e.g. C8:24:70:AB:CD:EF> [--disc]

Prints writes (TX, phone -> speaker) and notifications/read responses (RX).
--disc also prints GATT discovery PDUs (service/characteristic/descriptor lookups).
"""
import datetime
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from btsnoop_rfcomm import records  # noqa: E402

OPS = {
    0x01: "ERR", 0x02: "MTU_REQ", 0x03: "MTU_RSP", 0x04: "FIND_INFO_REQ", 0x05: "FIND_INFO_RSP",
    0x08: "READ_BY_TYPE_REQ", 0x09: "READ_BY_TYPE_RSP", 0x0A: "READ_REQ", 0x0B: "READ_RSP",
    0x10: "READ_BY_GROUP_REQ", 0x11: "READ_BY_GROUP_RSP", 0x12: "WRITE_REQ", 0x13: "WRITE_RSP",
    0x1B: "NOTIFY", 0x1D: "INDICATE", 0x1E: "CONFIRM", 0x52: "WRITE_CMD",
}
DISC = {0x01, 0x02, 0x03, 0x04, 0x05, 0x08, 0x09, 0x10, 0x11}


def uuid_str(b):
    if len(b) == 2:
        return f"{struct.unpack('<H', b)[0]:04X}"
    h = b[::-1].hex().upper()
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"


def main():
    path = sys.argv[1]
    if len(sys.argv) < 3 or sys.argv[2].startswith("--"):
        sys.exit("usage: btsnoop_att.py btsnoop_hci.log <speaker LE address> [--disc]")
    want = sys.argv[2].upper()
    disc = "--disc" in sys.argv
    handles = set()
    frag = {}
    for ts, rx, ptype, d in records(path):
        if ptype == 4 and d[0] == 0x3E and len(d) >= 14 and d[2] in (0x01, 0x0A) and d[3] == 0:
            h = struct.unpack("<H", d[4:6])[0] & 0x0FFF
            addr = ":".join(f"{x:02X}" for x in reversed(d[8:14]))
            if addr == want:
                handles.add(h)
                print(f"# LE connection handle {h:#x} to {addr}")
            else:
                handles.discard(h)
            continue
        if ptype != 2 or len(d) < 4:
            continue
        hf, ln = struct.unpack("<HH", d[:4])
        h, pb = hf & 0x0FFF, (hf >> 12) & 3
        if h not in handles:
            continue
        key = (h, rx)
        body = d[4:4 + ln]
        if pb in (0, 2):
            frag[key] = bytearray(body)
        elif key in frag:
            frag[key] += body
        else:
            continue
        buf = frag[key]
        if len(buf) < 4:
            continue
        l2len, cid = struct.unpack("<HH", buf[:4])
        if len(buf) < 4 + l2len:
            continue
        pdu = bytes(buf[4:4 + l2len])
        del frag[key]
        if cid != 4 or not pdu:
            continue
        op = pdu[0]
        if op in DISC and not disc:
            continue
        t = datetime.datetime.fromtimestamp(ts / 1e6).strftime("%H:%M:%S.%f")[:-3]
        name = OPS.get(op, f"op{op:#x}")
        dirn = "RX" if rx else "TX"
        if op in (0x12, 0x52, 0x1B, 0x1D) and len(pdu) >= 3:
            ah = struct.unpack("<H", pdu[1:3])[0]
            print(f"{t} {dirn} {name:<9} h={ah:#06x} {pdu[3:].hex(' ')}")
        elif op == 0x11 and len(pdu) > 2:
            n = pdu[1]
            for i in range(2, len(pdu) - n + 1, n):
                s, e = struct.unpack("<HH", pdu[i:i + 4])
                print(f"{t} {dirn} SERVICE   {s:#06x}-{e:#06x} {uuid_str(pdu[i + 4:i + n])}")
        elif op == 0x09 and len(pdu) > 2:
            n = pdu[1]
            for i in range(2, len(pdu) - n + 1, n):
                ah, props, vh = struct.unpack("<HBH", pdu[i:i + 5])
                print(f"{t} {dirn} CHAR      decl={ah:#06x} props={props:#04x} value={vh:#06x} {uuid_str(pdu[i + 5:i + n])}")
        elif op == 0x05 and len(pdu) > 2:
            fmt = 2 if pdu[1] == 1 else 16
            for i in range(2, len(pdu) - fmt - 1, fmt + 2):
                ah = struct.unpack("<H", pdu[i:i + 2])[0]
                print(f"{t} {dirn} DESC      {ah:#06x} {uuid_str(pdu[i + 2:i + 2 + fmt])}")
        else:
            print(f"{t} {dirn} {name:<9} {pdu[1:].hex(' ')}")


if __name__ == "__main__":
    main()
