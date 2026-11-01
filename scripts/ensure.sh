#!/bin/sh
# Runs in the Ubuntu guest, as root, from the systemd service wslg-weston.service at every WSL start.
# Makes sure that WSLg runs the custom Weston: installs the wrapper into the WSLg system distro if it is not there
# (the system distro starts from a read-only image), restarts Weston once if the running one is not the custom build,
# and starts msrdc by hand if WSLGd does not run one. Idempotent, every wait is bounded.
# Log: $WORK/ensure.log     Stop it without touching systemd:  touch <repo>/DISABLE
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
mkdir -p "$WORK"
LOG=$WORK/ensure.log
if [ -e "$REPO/DISABLE" ]; then echo "$(date '+%F %T') disabled by $REPO/DISABLE" >>"$LOG"; exit 0; fi
exec 9>/run/wslg-weston-ensure.lock
flock -n 9 || exit 0
exec >>"$LOG" 2>&1
log() { echo "$(date '+%F %T') $*"; }

WSLEXE=/mnt/c/Windows/System32/wsl.exe
DISTRO=${WSL_DISTRO_NAME:-Ubuntu}
STAGE=/mnt/wslg/distro$REPO/scripts     # the same files, as seen from the system distro
DONE=/run/wslg-weston-ensure.done      # /run is cleared at every boot of this distro

# a service has no WSL_INTEROP and no Windows directory in PATH: find a socket that works
pick_interop() {
	for s in $(ls -t /run/WSL/*_interop 2>/dev/null); do
		if [ "$(WSL_INTEROP=$s timeout 15 $WSLEXE --system -d "$DISTRO" -u root -e echo reached 2>/dev/null | tr -d '\0' | grep -c '^reached')" = 1 ]; then
			export WSL_INTEROP=$s; return 0
		fi
	done
	return 1
}
sys() { timeout "${SYS_TIMEOUT:-90}" "$WSLEXE" --system -d "$DISTRO" -u root -e "$@" 2>/dev/null | tr -d '\0'; }
# wait_for SECONDS COMMAND...: run COMMAND in the system distro until it prints "ok"
wait_for() { n=$1; shift; i=0; while [ "$i" -lt "$n" ]; do [ "$(sys "$@")" = ok ] && return 0; sleep 3; i=$((i+3)); done; return 1; }

log "--- ensure.sh start (boot $(cat /proc/sys/kernel/random/boot_id | cut -c1-8))"

i=0; until pick_interop; do i=$((i+5)); [ "$i" -ge 120 ] && { log "no usable interop socket after 120 s: giving up"; exit 1; }; sleep 5; done
log "interop: $WSL_INTEROP"

wait_for 180 sh -c 'pgrep -x WSLGd >/dev/null && pgrep -f -- '--socket=wayland-[0]' >/dev/null && echo ok' \
	|| { log "WSLGd / Weston did not come up within 180 s: giving up"; exit 1; }
log "WSLGd and a Weston are running"

if [ "$(sys sh -c 'grep -q weston-original /usr/bin/weston 2>/dev/null && echo ok')" = ok ]; then
	log "wrapper already installed"
else
	log "installing the wrapper: $(sys sh "$STAGE/install.sh" | sed -n 1p)"
fi

custom_running='for p in $(pgrep -f -- "--socket=wayland-[0]"); do tr "\0" " " </proc/$p/cmdline | grep -q "weston-rail/bin/[w]eston" && echo ok; done'

# WSLGd runs `xset` (font setup for Xwayland) synchronously in its main loop. If Weston is killed while one is running, the
# xset hangs on the dead X server for good, WSLGd stops supervising, nothing restarts Weston and no GUI ever comes (seen at the
# first real boot with this service). So: do not touch Weston before WSLGd has finished starting (it launches msrdc then) nor
# while an xset runs, and if one hangs after the switch anyway, kill it.
wslgd_settled() {
	wait_for 120 sh -c 'pgrep -f "msrdc[.]exe /wslg" >/dev/null && echo ok' || log "WSLGd did not launch msrdc within 120 s: going on anyway"
	wait_for 60 sh -c '[ -z "$(pgrep -x xset)" ] && echo ok' || log "an xset is still running after 60 s: going on anyway"
	sleep 5
}
unstick_wslgd() {
	sys sh -c 'W=$(pgrep -x WSLGd); for p in $(pgrep -x xset); do if [ "$(ps -o ppid= -p $p | tr -d " ")" = "$W" ] && [ "$(ps -o etimes= -p $p | tr -d " ")" -gt 8 ]; then echo "killing the hung xset $p"; kill -TERM $p; fi; done'
}

if [ "$(sys sh -c "$custom_running" | sed -n 1p)" = ok ]; then
	log "the custom Weston is already running"
elif [ -e "$DONE" ]; then
	log "not the custom Weston, but a switch was already done in this boot: leaving it alone (fallback in use?)"
else
	date >"$DONE"
	wslgd_settled
	log "switching to the custom Weston: $(sys sh "$STAGE/restart-weston.sh" | tr '\n' ' ' | cut -c1-120)"
	i=0; up=0
	while [ "$i" -lt 90 ]; do
		if [ "$(sys sh -c "$custom_running" | sed -n 1p)" = ok ]; then up=1; break; fi
		if [ "$i" -ge 9 ]; then m=$(unstick_wslgd); [ -n "$m" ] && log "$m"; fi
		sleep 3; i=$((i+3))
	done
	if [ "$up" = 1 ]; then log "the custom Weston is up"; else log "the custom Weston did not come up within 90 s (the wrapper falls back to the original)"; fi
fi

# WSLGd starts msrdc itself, unless it gave up ("exited more than 10 times in 60 seconds")
if wait_for 30 sh -c 'pgrep -f "msrdc[.]exe /wslg" >/dev/null && echo ok'; then
	log "msrdc is running"
else
	log "no msrdc: starting it by hand: $(sys sh "$STAGE/start-msrdc.sh" | tail -1 | cut -c1-80)"
fi
log "--- ensure.sh done"
