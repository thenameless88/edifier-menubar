# Edifier MR5 control protocol

Reverse-engineered from Android HCI snoop captures of the official **Edifier ConneX**
app (2026-11-25), each synchronised with a screen recording of the app.
MR5 firmware as shown by ConneX: **1.0.3** (classic BT reports 2.4.0).

> **Tested only with the Edifier MR5.** Other Edifier models (e.g. the MR3, which
> reports the same USB/BT vendor and product IDs) were **not tested** and may differ.
>
> **Test devices.** The captures were made with test devices. Their names and
> Bluetooth addresses are replaced throughout with placeholders: the speaker is
> `C8:24:78:AB:CD:EF` (classic) / `C8:24:70:AB:CD:EF` (LE); the paired sources are
> "Test Mac A" (`02:00:00:00:00:0A`), "Test Mac B" (`02:00:00:00:00:0C`) and
> "Test Phone" (`02:00:00:00:00:0B`). Frames containing them were re-encoded with
> correct checksums; all other bytes are exactly as captured.

**Only commands observed in the capture are listed. The menu bar app sends
nothing else.** No firmware/DFU, factory reset, power-off, prompt-tone or
Bluetooth-settings writes were captured, and none are implemented.

## 1. Transport

ConneX does **not** use the classic SPP/RFCOMM channels. It uses **BLE GATT**.

| | |
|---|---|
| Classic (A2DP/AVRCP) address | `C8:24:78:AB:CD:EF` |
| **LE address** (public) | **`C8:24:70:AB:CD:EF`** |
| Advertised name (scan response) | `EDIFIER BLE` |
| Advertised 16-bit service UUID | `0x3A01` |
| Manufacturer data | company `0x07E0`, then the classic MAC `C8 24 78 AB CD EF`, then `02 00` |
| ATT MTU | phone asked 517, speaker answered **200** |
| Write characteristic | ATT handle `0x0009`, **Write Without Response** |
| Notify characteristic | ATT handle `0x0006`, notifications |

Characteristic UUIDs were not in the capture (Android had GATT cached). The macOS
app discovers them at runtime: inside service `3A01` (or any service if that
fails) it picks the characteristic with *write without response* and the one
with *notify*.

The speaker apparently advertises only while no LE central is connected: close
ConneX (or turn phone Bluetooth off) before the Mac can see it.

No pairing, bonding, authentication or encryption handshake was observed: the
first application packet is a plain name query.

### Classic Bluetooth (unused by ConneX)

SDP: `JL_SPP` RFCOMM ch 10 (UUID `FE010000-1234-5678-ABCD-00805F9B34FB`),
`JL_SPP` RFCOMM ch 1 (`0x1101`), AVRCP (PSM 23), `JL_A2DP` sink (PSM 25),
Device ID. Chipset: Zhuhai JieLi. No traffic on the RFCOMM channels in the capture.
BLE was not visible to the Mac during the first scans because the phone held the
LE link.

## 2. Frame format

```
phone → speaker:  AA EC <cmd> 00 <len> <payload…> <sum>
speaker → phone:  BB EC <cmd> 00 <len> <payload…> <sum>
```

* `cmd` — one byte command code; replies echo it.
* `len` — payload length (one byte; the `00` before it may be a length high byte).
* `sum` — sum of **all preceding bytes** of the frame, mod 256.
  Example: `AA EC C9 00 00` → 0xAA+0xEC+0xC9 = 0x25F → `5F`.

Set commands get a short ack: `BB EC <cmd> 00 01 01 <sum>` (payload `01` = OK),
then the speaker usually pushes the updated state (unsolicited notifications).

## 3. Commands

### Queries (empty payload)

| cmd | Request | Reply payload | Meaning |
|---|---|---|---|
| `C9` | `AA EC C9 00 00 5F` | ASCII `EDIFIER MR5` | device name |
| `D5` | `AA EC D5 00 00 6B` | 7 bytes, see *Tuning state* | sound mode + acoustic tuning |
| `66` | `AA EC 66 00 00 FC` | `<max> <current>` e.g. `1E 15` = 21/30 | volume |
| `BB` | `AA EC BB 00 00 51` | `04 <ch>` | audio channel of the active speaker |
| `C3` | `AA EC C3 00 00 59` | `03`, `0D` | status (`0D` while play was pressed in ConneX, else `03`; also pushed unsolicited) — read-only |
| `D8` | `AA EC D8 00 00 6E` | 26 bytes | capability/feature blob — not decoded |
| `C6` | `AA EC C6 00 00 5C` | `01 00 03` | unknown, read-only |
| `68` | `AA EC 68 00 00 FE` | `05` | unknown, read-only |
| `C0` | `AA EC C0 00 00 56` | `00` | unknown, read-only |
| `61` | `AA EC 61 00 00 F7` | `04 01` | read on *My Device* page; unknown |
| `AD` | `AA EC AD 00 00 43` | paired device list | `02 02` then per device: `<len> <name> <6-byte addr>` (three test devices) |

ConneX's connect sequence: `C9, D8, C9, C6, C3, 68, D5, C0, 66`.

### Tuning state (`D5` reply / `C4` payload), 7 bytes

| byte | Meaning | Observed values |
|---|---|---|
| 0 | Sound mode | `00` Monitor, `01` Music, `02` Custom |
| 1 | unknown, constant | `02` |
| 2–3 | Low cutoff frequency, Hz, big-endian | `00 1E` 30, `00 28` 40, `00 32` 50 captured; ConneX slider range 20–100 Hz, default 30 Hz (confirmed by the user, used by the app) |
| 4 | Low cutoff slope | `00` −6, `01` −12, `02` −18, `03` −24 dB/oct |
| 5 | Acoustic space | `00` 0 dB, `01` −1, `02` −2, `03` −3, `04` −4 dB |
| 6 | Desktop Control | `00` off, `01` on |

### Set tuning — `C4`

`AA EC C4 00 07 <7 bytes tuning state> <sum>` — always the full state; ConneX
re-reads `D5` afterwards. Examples (all captured):

| Action (video time) | Frame |
|---|---|
| Sound mode → Monitor (≈0:04) | `AA EC C4 00 07 00 02 00 1E 03 00 00 84` |
| Sound mode → Music (≈0:09) | `AA EC C4 00 07 01 02 00 1E 03 00 00 85` |
| Sound mode → Custom (≈0:12) | `AA EC C4 00 07 02 02 00 1E 03 00 00 86` |
| Low cutoff 40 Hz (≈0:21) | `AA EC C4 00 07 01 02 00 28 03 00 00 8F` |
| Low cutoff 50 Hz (≈0:23) | `AA EC C4 00 07 01 02 00 32 03 00 00 99` |
| Slope −18 (≈0:29) | `AA EC C4 00 07 01 02 00 1E 02 00 00 84` |
| Slope −6 (≈0:32) | `AA EC C4 00 07 01 02 00 1E 00 00 00 82` |
| Acoustic space −4 dB (≈0:39) | `AA EC C4 00 07 01 02 00 1E 03 04 00 89` |
| Desktop Control ON (≈0:44) | `AA EC C4 00 07 01 02 00 1E 03 00 01 86` |
| Desktop Control OFF (≈0:48) | `AA EC C4 00 07 01 02 00 1E 03 00 00 85` |

Ack: `BB EC C4 00 01 01 6D`.

Selecting *Custom* opens a custom-EQ editor in ConneX; its EQ band writes were
not captured (the user returned to Music immediately), so custom EQ editing is
not implemented.

### Set volume — `67`

`AA EC 67 00 01 <vol> <sum>`, vol 0…30 (`1E`); all of 0–30 except a few
intermediate steps were observed. Ack `BB EC 67 00 01 01 10`, followed by an
unsolicited `66` volume report: `BB EC 66 00 02 1E <vol> <sum>`.
The speaker also pushes `66` when the volume changes from the knob/remote.

### Set audio channel — `BC`

`AA EC BC 00 02 04 <ch> <sum>`; `ch` `01` = active speaker is **right** channel
(default), `02` = **left**. Captured at video ≈1:13 (`04 02`, checksum `5A`)
and ≈1:16 (`04 01`, `59`). Ack `BB EC BC 00 01 01 65`.

### Second capture (2026-11-25 10:41–10:44, video t=0 ≈ 10:41:48.5)

#### Paired devices — `AD` (query), `AE` (connect), `AF` (disconnect)

`AD` reply payload: `<max> <connected> { <len> <name…> <addr ×6> }*`

* `max` = `02` (two simultaneous source devices), `connected` = number of
  connected devices, which are listed **first**.
* each entry: `len` = name length + 6, then UTF-8 name, then the BD_ADDR in
  little-endian order (`0A 00 00 00 00 02` = `02:00:00:00:00:0A`).
* The speaker pushes a fresh `AD` list after every change.

| Action (video time) | Frame | Reply |
|---|---|---|
| Disconnect "Test Mac A" (≈0:27, part of ConneX's "Connect Test Mac B" flow; Test Mac B then connected by itself) | `AA EC AF 00 06 0A 00 00 00 00 02 57` | `BB EC AF 00 01 01 58` |
| Disconnect "Test Mac B" (≈0:36, toggle off) | `AA EC AF 00 06 0C 00 00 00 00 02 59` | `BB EC AF 00 01 01 58` |
| Connect "Test Mac A" (≈0:41) | `AA EC AE 00 06 0A 00 00 00 00 02 56` | `BB EC AE 00 01 02 58` (in progress), later `BB EC AE 00 01 01 57` (done) |

"Unpair" was not captured and is not implemented.

#### HD audio codec (LDAC) — `91` (query), `92` (set)

`91` reply: `0F <codec>`; `92` request: `0F <codec> FF`, reply echoes `0F <codec>`.

| codec | ConneX label |
|---|---|
| `00` | Disable LDAC (default codec) |
| `01` | Sampling rate 44.1/48 kHz (initial setting) |
| `02` | Sampling rate 96 kHz |

| Action (video time) | Frame |
|---|---|
| 96 kHz + Save + Confirm (≈0:58) | `AA EC 92 00 03 0F 02 FF 3B` |
| Disable LDAC (≈1:37) | `AA EC 92 00 03 0F 00 FF 39` |
| 44.1/48 kHz (≈1:56) | `AA EC 92 00 03 0F 01 FF 3A` |

After a codec change the speaker drops all links (including BLE) and
reconnects; ConneX shows "The product will reconnect to the app".
ConneX also sends `AA EC 48 00 00 DE` four times on the codec page and gets no
reply; its meaning is unknown and the app does not send it.

### Third capture: custom EQ (2026-11-25 10:56–10:59, video t=0 ≈ 10:57:51)

ConneX's custom EQ editor: 9 bands, −3…+3 dB in 0.5 dB steps, a "Mode Selection"
base (Monitor/Music) underneath, and Reset. Selecting *Custom* itself is the `C4`
tuning command with byte 0 = `02`.

#### `43` — query custom EQ

Reply: `<maxStep> <count> <base> { <band> <freq hi> <freq lo> <step> }×count [<id ×4> <name…>]`

* `maxStep` = `0C` (12); gain step 0…12, **6 = 0 dB**, 0.5 dB per step.
* `count` = `09`; frequencies 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz.
* `base`: `00` Monitor, `01` Music.
* trailing: a 4-byte profile id (`E4 B0 06 6B`) and its ASCII name (`Sound Effects`)
  once ConneX has created the profile with `46` (see below).

Example (flat, Monitor): `BB EC 43 00 27 0C 09 00 00 00 3E 06 01 00 7D 06 … 08 3E 80 06 B8`

#### `44` — set one band

`AA EC 44 00 05 <base> <band> <freq hi> <freq lo> <step> <sum>`, ack `BB EC 44 00 01 01 ED`.
ConneX re-reads `43` after every write.

| Action (video time) | Frame |
|---|---|
| 62 Hz → +1 dB, Monitor base (≈0:01) | `AA EC 44 00 05 00 00 00 3E 08 25` |
| 125 Hz → +2 dB (≈0:11) | `AA EC 44 00 05 00 01 00 7D 0A 67` |
| 16 kHz → −3 dB (≈0:29) | `AA EC 44 00 05 00 08 3E 80 00 A5` |
| Base → Music (≈1:09; band 0 re-sent with base `01`) | `AA EC 44 00 05 01 00 00 3E 06 24` |
| 250 Hz → +3 dB, Music base (≈1:13) | `AA EC 44 00 05 01 02 00 FA 0C E8` |
| Base → Monitor (≈1:25; band 0 re-sent with base `00`) | `AA EC 44 00 05 00 00 00 3E 05 22` |

Switching the base is done by re-sending band 0 at its current gain with the new base byte.

#### `45` — reset custom EQ

`AA EC 45 00 00 DB` (after ConneX's "Reset … Confirm", ≈0:58 and ≈1:29).
Reply: `<base> { <band> <freq16> <step> }×9` — all steps `06`, base `00` (Monitor).

#### `46` — create/store EQ profile (observed, **not used by the app**)

Sent by ConneX when Custom was opened (10:56:52):
`AA EC 46 00 36 00 <9 × band entry> E4 B0 06 6B "Sound Effects" 92`; the speaker echoes it.
The app only edits the existing profile with `44`/`45`.

## 4. Not implemented / not observed

Power-saving mode, prompts & tones, power off, Bluetooth settings (disconnect),
unpair, factory settings, EQ profile create/rename/delete/share (`46` etc.), firmware update.
ConneX's MR5 UI has **no input-source selector**.

## 5. Tools

* `tools/btsnoop_att.py` — dumps ATT writes/notifications for one LE peer (`--disc` for GATT discovery).
* `tools/btsnoop_rfcomm.py` — RFCOMM payload extractor (found nothing for the MR5).
* `tools/blescan.swift`, `tools/sdp.swift` — macOS discovery helpers.
