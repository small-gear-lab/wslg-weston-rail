# Sourced by the scripts that run in the Ubuntu guest:  HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# Reads ../config.env (written by scripts/configure.sh): REPO, WORK, PREFIX, FREERDP_PREFIX (absolute paths in the guest).
REPO=$(cd "$HERE/.." && pwd)
if [ ! -f "$REPO/config.env" ]; then
	echo "$REPO/config.env is missing: run scripts/configure.sh first" >&2
	exit 1
fi
. "$REPO/config.env"
