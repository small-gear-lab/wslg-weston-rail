#!/bin/sh
# Run as root in the WSLg system distro:  wsl.exe --system -d Ubuntu -u root -e sh <this file>
# Puts the original weston binary back at /usr/bin/weston (overlayfs: rm would not restore it).
set -eu
ORIG=/usr/libexec/weston-original
[ -f "$ORIG" ] || { echo "no saved original at $ORIG (restart WSL: wsl --shutdown)"; exit 1; }
cp -p "$ORIG" /usr/bin/weston.new && mv -f /usr/bin/weston.new /usr/bin/weston
echo "restored: sha256 now $(sha256sum /usr/bin/weston | cut -d' ' -f1), saved original $(cat /usr/libexec/weston-original.sha256)"
