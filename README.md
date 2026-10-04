# camera-scan

A Claude Code / Agent skill to **detect hidden or networked surveillance cameras on the WiFi/LAN you're connected to** — then identify them and pull a live frame so you can see exactly what each one is pointed at.

Built for a real situation: you walk into a hotel room, Airbnb, or rental and want to know if something on the network is watching you.

> ⚠️ **Authorized use only.** Run this only on a network you own or are lawfully occupying. It's a defensive privacy tool for finding devices that may be watching *you* — not for probing networks or devices you have no right to access.

## What it does

1. **Discover** — maps every live device on the local `/24`, reads each MAC, and tags it `[VENDOR]` (real hardware, could be a camera) vs `[RANDOM]` (a phone/laptop using MAC randomization). Scans each host for camera/DVR ports (RTSP 554, ONVIF 8000, and cheap-DVR ports 34567/37777/8899…), **and** matches each MAC's manufacturer (OUI) against a bundled list of known camera vendors — so it also flags **cloud/app cameras that expose no local port** (most modern consumer cams and cheap "spy cams" stream outbound to an app; a port scan alone never sees them).
2. **Fingerprint** — sends `OPTIONS * RTSP/1.0` to read the device's `Server:` header (usually names the vendor: TVT, Dahua, Hikvision…), then brute-forces a large RTSP path dictionary to find the live stream URL.
3. **Pull frames** — enumerates DVR channels and grabs a clean frame from each with `ffmpeg`, so you can *see* the view (street? stairwell? your bedroom? your balcony?).
4. **Classify & report** — outdoor CCTV vs indoor common area vs 🚩 private space, whether audio (a mic) is present, with timestamped frames as evidence.

## Why network-only isn't enough

The scan sees cameras on the **same WiFi/LAN** only. It misses cameras on a separate VLAN, on their own hidden hotspot, or wired/analog. Big hotels often use client isolation, which hides everything (if you *do* see other devices, isolation is off and results are meaningful). Finish with a quick **physical lens sweep** (lights off, phone camera, look for IR dots) for certainty about the room interior.

## Requirements

- macOS or Linux
- `perl` (built in) + `ffmpeg` / `ffprobe` (`brew install ffmpeg`)
- No `nmap` needed — raw sockets.

## Usage

Drop the folder into `~/.claude/skills/camera-scan/` and trigger with `/camera-scan`, or run the scripts directly:

```bash
# 1. discover devices + camera ports
bash scripts/scan.sh

# 2. fingerprint a suspect + find its stream path
perl scripts/rtsp_probe.pl 10.0.0.50

# 3. pull a frame from every channel of a DVR ({CH} = channel placeholder)
bash scripts/grab.sh 'rtsp://10.0.0.50:554/chID={CH}&streamType=main' 8
```

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Skill definition + step-by-step workflow for the agent |
| `scripts/scan.sh` | Network discovery, MAC classification, camera-port scan + vendor-OUI flag |
| `scripts/camera_ouis.txt` | Offline MAC-OUI → known-camera-vendor list (from the IEEE registry) |
| `scripts/rtsp_probe.pl` | RTSP vendor fingerprint + stream-path brute-force |
| `scripts/grab.sh` | Per-channel `ffmpeg` frame capture |

## Legal note

Undisclosed cameras covering private areas of rented accommodation violate Airbnb/booking-platform policy and, in many jurisdictions (e.g. Israel — חוק הגנת הפרטיות), the law. Saved frames + timestamps are usable evidence for a platform complaint or police report.

## License

MIT
