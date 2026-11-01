#!/bin/sh
# Writes config.env: where the sources, the build and the installed Weston/FreeRDP live. Run it once, as the user.
# Environment overrides:  WORK (sources and build dirs, default <repo>/work)
#                         PREFIX (install prefix of Weston, default ~/.local/opt/weston-rail)
#                         FREERDP_PREFIX (install prefix of FreeRDP, default ~/.local/opt/freerdp-gfx)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
cat >"$REPO/config.env" <<CONF
REPO=$REPO
WORK=${WORK:-$REPO/work}
PREFIX=${PREFIX:-$HOME/.local/opt/weston-rail}
FREERDP_PREFIX=${FREERDP_PREFIX:-$HOME/.local/opt/freerdp-gfx}
CONF
echo "wrote $REPO/config.env:"; cat "$REPO/config.env"
