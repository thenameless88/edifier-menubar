#!/usr/bin/env python3
"""Extract RFCOMM payloads from an Android btsnoop_hci.log (no Wireshark needed).

Usage: python3 tools/btsnoop_rfcomm.py btsnoop_hci.log [--addr C8:24:78:AB:CD:EF] [--all]

Prints one line per RFCOMM UIH data frame:
  <local time>  <TX|RX>  dlci=<n> ch=<n>  <hex payload>
TX = phone -> speaker, RX = speaker -> phone.
"""
import struct
import sys
import datetime
from collections import defaultdict

EPOCH_DELTA_US = 0x00DCDDB30F2F8000  # btsnoop epoch (0 AD) -> unix epoch


def records(path):
    with open(path, "rb") as f:
        hdr = f.read(16)
        assert hdr[:8] == b"btsnoop\0", "not a btsnoop file"
        datalink = struct.unpack(">I", hdr[12:16])[0]
        while True:
            rh = f.read(24)
            if len(rh) < 24:
                return
            orig, incl, flags, drops, ts = struct.unpack(">IIIIq", rh)
            data = f.read(incl)
            if datalink == 1002:  # H4: first byte is packet type
                ptype, data = data[0], data[1:]
            else:  # 1001 = un-encapsulated HCI, type from flags
                ptype = 4 if flags & 2 and flags & 1 else (1 if flags & 2 else 2)
            yield ts - EPOCH_DELTA_US, flags & 1, ptype, data


def main():
    args = sys.argv[1:]
    path = args[0]
    want_addr = None
    if "--addr" in args:
        want_addr = args[args.index("--addr") + 1].upper()
    show_all = "--all" in args

    handle_addr = {}               # ACL handle -> BD_ADDR string
    frag = {}                      # (handle, dir) -> bytearray being reassembled
    psm_of = {}                    # (handle, cid) -> psm   (cid as seen on the wire for that direction)
    pending = {}                   # (handle, ident) -> (psm, scid, dir)
    for ts, rx, ptype, d in records(path):
        if ptype == 4 and len(d) >= 2:  # HCI event
            code = d[0]
            if code == 0x03 and len(d) >= 13 and d[2] == 0:  # Connection Complete
                h = struct.unpack("<H", d[3:5])[0] & 0x0FFF
                handle_addr[h] = ":".join(f"{b:02X}" for b in reversed(d[5:11]))
            elif code == 0x3E and len(d) >= 14 and d[2] in (0x01, 0x0A) and d[3] == 0:
                h = struct.unpack("<H", d[4:6])[0] & 0x0FFF
                handle_addr[h] = ":".join(f"{b:02X}" for b in reversed(d[8:14]))
            continue
        if ptype != 2 or len(d) < 4:
            continue
        hf, ln = struct.unpack("<HH", d[:4])
        h, pb = hf & 0x0FFF, (hf >> 12) & 3
        body = d[4:4 + ln]
        key = (h, rx)
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

        if cid == 1:  # L2CAP signalling
            i = 0
            while i + 4 <= len(pdu):
                code, ident, clen = pdu[i], pdu[i + 1], struct.unpack("<H", pdu[i + 2:i + 4])[0]
                p = pdu[i + 4:i + 4 + clen]
                if code == 0x02 and len(p) >= 4:  # Connection Request
                    psm, scid = struct.unpack("<HH", p[:4])
                    pending[(h, ident)] = (psm, scid, rx)
                elif code == 0x03 and len(p) >= 8:  # Connection Response
                    dcid, scid, result = struct.unpack("<HHH", p[:6])
                    if result == 0 and (h, ident) in pending:
                        psm, _, req_rx = pending.pop((h, ident))
                        # requester sends to dcid, responder sends to scid
                        psm_of[(h, req_rx, dcid)] = psm
                        psm_of[(h, 1 - req_rx, scid)] = psm
                i += 4 + clen
            continue

        if psm_of.get((h, rx, cid)) != 3:
            continue
        addr = handle_addr.get(h, f"handle{h:#x}")
        if want_addr and addr != want_addr:
            continue
        if len(pdu) < 3:
            continue
        a, ctrl = pdu[0], pdu[1]
        dlci = a >> 2
        if (ctrl & 0xEF) != 0xEF:  # only UIH frames carry data
            continue
        if pdu[2] & 1:
            plen, off = pdu[2] >> 1, 3
        else:
            plen, off = (pdu[2] >> 1) | (pdu[3] << 7), 4
        if ctrl & 0x10 and dlci != 0:  # credit byte
            off += 1
        payload = pdu[off:off + plen]
        if dlci == 0 and not show_all:
            continue
        if not payload and not show_all:
            continue
        t = datetime.datetime.fromtimestamp(ts / 1e6).strftime("%H:%M:%S.%f")[:-3]
        print(f"{t}  {'RX' if rx else 'TX'}  {addr} dlci={dlci:<2} ch={dlci >> 1:<2} {payload.hex(' ')}")


if __name__ == "__main__":
    main()
