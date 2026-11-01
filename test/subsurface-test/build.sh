#!/bin/sh
# Builds the test client. Needs wayland-scanner, libwayland-dev and wayland-protocols.
set -eu
cd "$(dirname "$0")"
PR=${WAYLAND_PROTOCOLS:-/usr/share/wayland-protocols}
for x in stable/xdg-shell/xdg-shell stable/viewporter/viewporter staging/single-pixel-buffer/single-pixel-buffer-v1; do
	n=$(basename "$x")
	wayland-scanner client-header "$PR/$x.xml" "$n.h"
	wayland-scanner private-code "$PR/$x.xml" "$n.c"
done
gcc -Wall -o subsurface-test subsurface-test.c xdg-shell.c viewporter.c single-pixel-buffer-v1.c $(pkg-config --cflags --libs wayland-client)
echo "built ./subsurface-test"
