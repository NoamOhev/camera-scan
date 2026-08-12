#!/usr/bin/env perl
# rtsp_probe.pl <ip> [port]
# 1) OPTIONS * -> read the RTSP Server: header (identifies the vendor).
# 2) Brute-force a large RTSP path dictionary -> print paths returning 200 / video SDP.
# Authorized use only: run against devices on a network you own or are lawfully occupying.
use strict; use warnings;
use IO::Socket::INET;
$SIG{PIPE} = 'IGNORE';

my $ip   = shift or die "usage: rtsp_probe.pl <ip> [port]\n";
my $port = shift || 554;

# --- 1) vendor fingerprint via OPTIONS * ---
print "== $ip:$port ==\n";
{
  my $s = IO::Socket::INET->new(PeerAddr=>$ip, PeerPort=>$port, Proto=>"tcp", Timeout=>4);
  if (!$s) { print "  TCP connect failed on $port — not open / filtered.\n"; exit 1; }
  syswrite($s, "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: LibVLC/3.0\r\n\r\n");
  my $buf = "";
  eval { local $SIG{ALRM} = sub { die }; alarm 4; sysread($s, $buf, 2048); alarm 0; };
  close($s);
  if ($buf =~ /Server:\s*([^\r\n]+)/i) {
    print "  Server: $1   <<< vendor fingerprint\n";
  } elsif ($buf) {
    print "  (responded, no Server header)\n";
  } else {
    print "  (no OPTIONS response)\n";
  }
}

# --- 2) path dictionary ---
my @paths = qw(
  / /0 /1 /11 /12 /ch0 /ch1 /ch01 /ch01/0 /ch01/1 /ch0_0.264 /ch0_1.264
  /ch1_0.264 /ch1_1.264 /live /live/main /live/sub /live/ch0 /live/ch00_0
  /live/ch01_0 /live0.264 /live1.264 /live/av0 /live/av1 /av0_0 /av0_1
  /media/video1 /media/video2 /profile1 /profile2 /stream1 /stream2
  /streaming/channels/1 /streaming/channels/101 /h264 /h264_stream /mpeg4
  /main /sub /1/1 /video /video1 /vod/1 /onvif1 /onvif2
  /unicast/c1/s0/live /snl/live/1/1/n /snl/live/1/0/n /11/h264major
  /ipcam.sdp /ipcam_h264.sdp /axis-media/media.amp /nphMpeg4/g726-640x480
);
my @qpaths = (
  "/cam/realmonitor?channel=1&subtype=0",
  "/cam/realmonitor?channel=1&subtype=1",
  "/chID=1&streamType=main",
  "/chID=1&streamType=sub",
  "/chID=1&streamType=main&linkType=tcp",
);

sub sockw { my ($s,$d)=@_; my $r; eval { local $SIG{ALRM}=sub{die}; alarm 3; $r=syswrite($s,$d); alarm 0; }; return defined($r); }

# Proper OPTIONS -> DESCRIBE sequence on one connection (some devices require it).
sub probe {
  my $p = shift;
  my $s = IO::Socket::INET->new(PeerAddr=>$ip, PeerPort=>$port, Proto=>"tcp", Timeout=>3) or return "NOCONN";
  binmode($s);
  sockw($s, "OPTIONS rtsp://$ip:$port$p RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: probe\r\n\r\n") or (close($s), return "WFAIL");
  my $b=""; eval { local $SIG{ALRM}=sub{die}; alarm 3; sysread($s,$b,2048); alarm 0; };
  unless (sockw($s, "DESCRIBE rtsp://$ip:$port$p RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: probe\r\nAccept: application/sdp\r\n\r\n")) { close($s); return "CLOSED"; }
  my $d=""; eval { local $SIG{ALRM}=sub{die}; alarm 3; while (sysread($s,my $x,4096)) { $d.=$x; last if length($d)>4000 || $d=~/m=video/s; } alarm 0; };
  close($s);
  my ($status) = $d =~ m{RTSP/1\.0 (\d{3})};
  $status ||= ($d eq "" ? "EMPTY" : "??");
  my $vid = ($d =~ /m=video/) ? "  <<<<< HAS VIDEO SDP" : "";
  my $aud = ($d =~ /m=audio/) ? " +AUDIO(mic)" : "";
  return "$status$vid$aud";
}

print "  Brute-forcing stream paths (non-404 shown):\n";
my $hits = 0;
for my $p (@paths, @qpaths) {
  my $r = probe($p);
  next if $r eq "404";
  $hits++;
  printf "    %-30s %s\n", $r, $p;
}
print "    (no non-404 paths found — device may need credentials, or a vendor-specific path)\n" unless $hits;
print "  Done. Use a 'HAS VIDEO SDP' path with grab.sh to pull frames.\n";
