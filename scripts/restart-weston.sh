#!/bin/sh
# Run as root in the WSLg system distro. Stops WSLg's Weston; WSLGd starts it again (through /usr/bin/weston).
# ALL WSLg GUI windows close.   DRYRUN=1 only prints what would be stopped.
#
# The process name is not reliable: it is "weston", "weston-original" (the fallback) or the name of the Ubuntu
# loader (the custom build). WSLg's own Weston is the only one started with --socket=wayland-0 (test runs use
# other socket names), so match on that and on --backend=rdp-backend.so. Shells and helpers whose command line
# merely contains these words are skipped.
pids=$(pgrep -f -- '--socket=wayland-0' | while read p; do
	[ "$p" = "$$" ] && continue
	case "$(cat /proc/$p/comm 2>/dev/null)" in sh|bash|zsh|dash|env|wsl.exe|pgrep|pkill|grep) continue ;; esac
	tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | grep -q -- '--backend=rdp-backend.so' && echo $p
done)
if [ -z "$pids" ]; then
	echo "no WSLg weston found (nothing matched --socket=wayland-0 with --backend=rdp-backend.so)"
	exit 1
fi
[ -n "$DRYRUN" ] && verb="would stop" || verb="stopping"
echo "$verb:"; for p in $pids; do echo "  pid $p ($(cat /proc/$p/comm)): $(tr '\0' ' ' </proc/$p/cmdline | cut -c1-90)"; done
[ -n "$DRYRUN" ] && exit 0
kill -TERM $pids && echo "sent SIGTERM; WSLGd should restart weston through /usr/bin/weston"
