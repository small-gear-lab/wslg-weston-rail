#!/bin/sh
# Configure (once), build and install the patched Weston into $PREFIX (see config.env)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
P=$PREFIX
B=$WORK/build-weston
E="env -i HOME=$HOME PATH=/usr/bin:/bin LANG=C.UTF-8"
if [ ! -f "$B/build.ninja" ]; then
  $E meson setup "$B" "$WORK/weston-src" --prefix="$P" --libdir=lib \
    -Dbackend-drm=false -Dbackend-headless=false -Dbackend-pipewire=false -Dbackend-rdp=true \
    -Dscreenshare=false -Dbackend-vnc=false -Dbackend-wayland=false -Dbackend-x11=false \
    -Dbackend-default=rdp -Drenderer-gl=true -Dxwayland=true -Dsystemd=false -Dremoting=false \
    -Dpipewire=false -Dshell-desktop=true -Dshell-fullscreen=false -Dshell-ivi=false \
    -Dshell-kiosk=false -Dshell-rdprail=true -Dcolor-management-lcms=false -Dimage-jpeg=true \
    -Dimage-webp=false -Dimage-svg=true '-Dtools=[]' -Ddemo-clients=false '-Dsimple-clients=[]' \
    -Dtests=false -Ddoc=false
fi
$E ninja -C "$B"
$E ninja -C "$B" install
$E gcc -shared -fPIC -O2 -Wall -Wno-attributes $(env -i PATH=/usr/bin:/bin PKG_CONFIG_PATH="$P/lib/pkgconfig:$P/share/pkgconfig" pkg-config --cflags libweston-15) -o "$WORK/wslgd-notify.so" "$REPO/src/wslgd-notify.c" -L"$P/lib" -lweston-15 '-Wl,-rpath,$ORIGIN/..'
cp "$WORK/wslgd-notify.so" "$P/lib/weston/wslgd-notify.so"
