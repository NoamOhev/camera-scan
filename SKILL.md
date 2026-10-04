---
name: camera-scan
description: "Detect hidden/networked surveillance cameras on the local WiFi/LAN — discover devices, fingerprint RTSP/DVR streams, identify the vendor, and pull live frames to see what each camera views. For hotels, Airbnbs, rentals you occupy."
trigger: /camera-scan
---

# /camera-scan

Find surveillance cameras on the WiFi/LAN you're connected to, identify them, and — when a stream is reachable — pull a live frame so you can see exactly what each camera is pointed at (street? your room? your balcony?).

Built for a real situation: you walk into a hotel room / Airbnb and want to know if something on the network is watching you.

## ⚠️ Scope — authorized use only

Run this **only** on a network you own or are lawfully occupying (your home, a room/apartment you're renting and staying in). This is a defensive privacy tool for finding devices that may be watching *you*. Do not point it at networks or devices you have no right to access.

## What it can and can't see

- **Sees:** any camera/DVR/NVR that is on the same WiFi/LAN and not blocked by client isolation.
- **Misses:** cameras on a separate VLAN, on their own hidden hotspot, wired-only/analog cameras, or a network with AP/client isolation (common in big hotels). If the scan finds other devices at all, isolation is OFF and results are meaningful.
- A clean network scan does **not** 100% rule out a camera *inside the room* — finish with a quick physical lens sweep (below).

## Dependencies

- macOS/Linux with `perl` (built in) and `ffmpeg`/`ffprobe` (`brew install ffmpeg`).
- No `nmap` required — the scripts use raw sockets.

## Workflow

Run the steps in order. Scripts live in `scripts/` next to this file — resolve `$SKILL_DIR` to that folder.

### 1. Discover devices + scan camera ports
```bash
bash "$SKILL_DIR/scripts/scan.sh"
```
Prints: your interface/IP/gateway/SSID, every live host with its MAC, a **[RANDOM]** vs **[VENDOR]** tag per MAC, any open camera ports per host, and — new — a **known-camera-vendor** flag derived from the MAC's manufacturer (OUI).

Two independent ways a host gets flagged as a suspect:
- **`<<< CAMERA-LIKE PORT`** — a **[VENDOR]** MAC with a camera/DVR port open (554/8000/8554/34567/37777/8899…). These are **local-stream** cameras (RTSP/ONVIF/DVR) → go to Step 2 to pull the feed.
- **`>>> KNOWN CAMERA VENDOR` / `>>> CAMERA-CAPABLE MODULE`** — the MAC's manufacturer is a known camera maker (`CAM`, e.g. Hikvision/Dahua/IMILAB/Wyze/Reolink) or a WiFi-module maker common in cheap cams (`MODULE`, e.g. Shenzhen Bilian/Tuya — also used in bulbs/plugs, so "verify"). **This catches cloud/app cameras that expose NO local port** — the kind the port scan alone misses (most modern consumer cams and cheap "spy cams" stream *outbound* to an app, so there's no port to find). Vendor list: `scripts/camera_ouis.txt` (offline, from the IEEE OUI registry; not exhaustive).

Interpreting the two together:
- **VENDOR-vendor-flagged _with_ a camera port** = strongest signal; fingerprint it (Step 2).
- **Vendor-flagged with _no_ open port** = likely a cloud/app cam. The scan can't see its video (it's not serving locally). Account for it (your own gear?) or confirm with a **physical lens sweep** (below). Skip Step 2 — there's no local stream to probe.
- **[RANDOM]** MACs (locally-administered bit set) = phones/laptops with MAC randomization → almost never cameras. Note: a camera using MAC randomization won't match the vendor list either — another reason the physical sweep matters.
- The gateway with port 80 is just the router — normal.

### 2. Fingerprint each suspect
```bash
perl "$SKILL_DIR/scripts/rtsp_probe.pl" <SUSPECT_IP>
```
Sends `OPTIONS * RTSP/1.0` (note the `*` — many devices stay silent without it) to read the **`Server:` header**, which usually names the vendor (TVT, Hipcam, Dahua, Hikvision, H264DVR…). Then brute-forces a large RTSP path dictionary (plain + query-string styles) and prints every path that returns **200** or advertises a **video SDP** — those are the live stream URLs. A `404` means wrong path; `401` means right path but needs credentials.

### 3. Pull live frames (see what it watches)
Once you have a working stream URL, grab a frame per channel. Use `{CH}` as the channel placeholder:
```bash
bash "$SKILL_DIR/scripts/grab.sh" '<STREAM_URL_TEMPLATE>' [MAX_CHANNELS]
# e.g. TVT DVR:
bash "$SKILL_DIR/scripts/grab.sh" 'rtsp://10.0.0.50:554/chID={CH}&streamType=main' 8
```
For a single camera (not a multi-channel DVR), pass the exact URL with no `{CH}`. The script grabs a **clean late frame** per channel (avoids the corrupted-color first-keyframe problem on HEVC), saves `cam_chN.jpg`, and opens them.

### 4. Read + classify each frame
Open each saved frame (Read tool or `open cam_ch*.jpg`) and classify what it shows:
- **Outdoor** (street/alley/facade) → property/street CCTV, low concern.
- **Indoor common area** (stairwell, lobby) → shared surveillance, note it.
- **Private space** (bedroom, bathroom, your balcony/terrace) → 🚩 real privacy problem. This is what matters.

Black frames = disconnected/covered/night cameras with no light.

### 5. Report
Give a per-channel map (Camera N → what it views), a clear verdict on whether anything watches a private space, note if **audio** is present in the SDP (mic = it records sound too), and keep the timestamped frames as evidence. Capturing the same channel again minutes later proves it's a **live** feed, not old footage.

If nothing networked is found but the user wants certainty about the room interior: **physical lens sweep** — lights off, phone camera (front cam filters IR less), scan for faint purple/white IR dots; flashlight at an angle for lens glints.

## Legal note (for the report, not advice)

Undisclosed cameras covering private areas of rented accommodation violate Airbnb/booking-platform policy and, in many jurisdictions (e.g. Israel — חוק הגנת הפרטיות), the law. The saved frames + timestamps are usable evidence for a platform complaint or police report.
