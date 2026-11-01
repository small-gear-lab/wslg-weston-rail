#!/bin/sh
# Run as root in the WSLg system distro:  wsl.exe --system -d Ubuntu -u root -e sh <this file>
# Saves the original /usr/bin/weston and puts the wrapper in its place. Does NOT restart Weston.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)       # <repo>/scripts, seen from the system distro
U=/mnt/wslg/distro
REPOG=${HERE%/scripts}; REPOG=${REPOG#$U}   # the repository as seen in the Ubuntu guest
ORIG=/usr/libexec/weston-original
if [ ! -e "$ORIG" ]; then
	# only save it if /usr/bin/weston is still the original ELF binary
	head -c4 /usr/bin/weston | grep -q ELF || { echo "refusing: /usr/bin/weston is not the original ELF"; exit 1; }
	cp -p /usr/bin/weston "$ORIG"
	sha256sum /usr/bin/weston | cut -d' ' -f1 > /usr/libexec/weston-original.sha256
fi
sed "s|@REPO@|$REPOG|g" "$HERE/weston-wrapper" >/usr/bin/weston.new && chmod 755 /usr/bin/weston.new && mv -f /usr/bin/weston.new /usr/bin/weston
echo "installed. original saved as $ORIG (sha256 $(cat /usr/libexec/weston-original.sha256))"
head -2 /usr/bin/weston
