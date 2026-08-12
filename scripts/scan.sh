#!/usr/bin/env bash
# scan.sh — discover live hosts on the local /24 and scan them for camera ports.
# Authorized use only: run on a network you own or are lawfully occupying.
# No nmap required. macOS + Linux.
set -u

# --- locate interface / IP / gateway / SSID ---
if command -v route >/dev/null 2>&1 && route -n get default >/dev/null 2>&1; then
  IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  GW=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
else
  IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
  GW=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
fi
[ -z "${IFACE:-}" ] && IFACE=en0

if command -v ipconfig >/dev/null 2>&1; then
  MYIP=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
fi
[ -z "${MYIP:-}" ] && MYIP=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)

SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/ SSID:/{print $2}')
[ -z "${SSID:-}" ] && SSID=$(networksetup -getairportnetwork "$IFACE" 2>/dev/null | sed 's/^.*: //')

if [ -z "${MYIP:-}" ]; then echo "Could not determine local IP on $IFACE"; exit 1; fi
SUBNET=$(echo "$MYIP" | awk -F. '{print $1"."$2"."$3}')

echo "=================================================="
echo " Interface : $IFACE"
echo " Local IP  : $MYIP"
echo " Gateway   : ${GW:-?}"
echo " SSID      : ${SSID:-?}"
echo " Scanning  : ${SUBNET}.0/24"
echo "=================================================="

# --- ping sweep to populate the ARP table ---
echo "Ping sweep (populating ARP)..."
for i in $(seq 1 254); do ping -c1 -W1 -t1 "${SUBNET}.$i" >/dev/null 2>&1 & done
wait 2>/dev/null

# --- camera / DVR ports worth checking ---
PORTS="80 81 88 443 554 8000 8080 8081 8443 8554 8899 9000 34567 37777 37778 8888 49152"

# tiny perl TCP connect with timeout (portable, no nc/nmap)
check_port() {
  perl -e 'use IO::Socket::INET;
    exit(IO::Socket::INET->new(PeerAddr=>$ARGV[0],PeerPort=>$ARGV[1],Proto=>"tcp",Timeout=>1.5)?0:1)' "$1" "$2" 2>/dev/null
}

# --- read ARP, classify MACs, port-scan each host ---
echo ""
echo "Live hosts (${SUBNET}.x):"
echo "--------------------------------------------------"
arp -a -n 2>/dev/null | grep -oE "\(${SUBNET}\.[0-9]+\) at ([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}" | while read -r entry; do
  ip=$(echo "$entry"  | grep -oE "${SUBNET}\.[0-9]+")
  mac=$(echo "$entry" | grep -oE '([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}')
  # skip broadcast / multicast noise
  [ "$ip" = "${SUBNET}.255" ] && continue
  [ "$mac" = "ff:ff:ff:ff:ff:ff" ] && continue
  [ "$ip" = "$MYIP" ] && tag="(this device)" || tag=""

  # MAC randomization: locally-administered bit = 0x02 of the first octet
  first=$(echo "$mac" | cut -d: -f1)
  dec=$(printf '%d' "0x$first" 2>/dev/null || echo 0)
  if [ $(( dec & 2 )) -ne 0 ]; then kind="[RANDOM]"; else kind="[VENDOR]"; fi
  [ "$ip" = "${GW:-}" ] && kind="[ROUTER]"

  # scan ports
  open=""
  for p in $PORTS; do check_port "$ip" "$p" && open="$open $p"; done
  # flag camera-like ports — but never on the router (its admin ports aren't cameras)
  flag=""
  if [ "$kind" != "[ROUTER]" ]; then
    echo "$open" | grep -qE '(^| )(554|8554|8000|34567|37777|37778|8899)( |$)' && flag="  <<< CAMERA-LIKE PORT"
  fi

  printf "  %-14s %-18s %-9s%s\n" "$ip" "$mac" "$kind" "$tag"
  [ -n "$open" ] && printf "        open ports:%s%s\n" "$open" "$flag"
done
echo "--------------------------------------------------"
echo "Next: perl rtsp_probe.pl <IP> on any [VENDOR] host with a camera-like port."
