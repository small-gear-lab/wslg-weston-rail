#!/bin/sh
# Installs and enables the systemd service that re-applies the custom Weston at every start of this distro
# (the system distro of WSLg is rebuilt from a read-only image at each WSL start). Run with sudo.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
sed "s|@REPO@|$REPO|g" "$REPO/systemd/wslg-weston.service.in" >/etc/systemd/system/wslg-weston.service
systemctl daemon-reload
systemctl enable wslg-weston.service
echo "enabled. It runs at the next start of the distro; to run it now: systemctl start wslg-weston.service"
