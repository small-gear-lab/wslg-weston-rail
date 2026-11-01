#!/bin/sh
# Gets the sources into $WORK:
#   weston-src   upstream Weston at the commit the patches are made against, + MR !1667 (unmodified) + our patches
#   freerdp-src  the distribution's FreeRDP 3 source (Ubuntu patches applied); needs a deb-src entry in apt sources
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
WESTON_URL=${WESTON_URL:-https://gitlab.freedesktop.org/wayland/weston.git}
WESTON_BASE=9d841e39      # the MR and our patches apply to this commit (14.0.91+579); newer commits conflict
mkdir -p "$WORK"
if [ ! -d "$WORK/weston-src/.git" ]; then
	git clone "$WESTON_URL" "$WORK/weston-src"
fi
cd "$WORK/weston-src"
if git rev-parse -q --verify refs/heads/rail >/dev/null; then
	echo "branch 'rail' exists in $WORK/weston-src: leaving it alone"
else
	git checkout -q -b rail "$WESTON_BASE"
	AM="git -c user.name=wslg-weston-rail -c user.email=noreply@invalid am --3way"
	$AM "$REPO/patches/mr1667/1667.patch"
	for p in "$REPO"/patches/local/*.patch; do $AM "$p"; done
	git log --oneline "$WESTON_BASE"..HEAD
fi
if [ ! -d "$WORK/freerdp-src" ]; then
	d=$(mktemp -d "$WORK/freerdp-fetch.XXXXXX")
	(cd "$d" && apt-get source freerdp3)
	mv "$d"/freerdp3-*/ "$WORK/freerdp-src"
	rm -rf "$d"
fi
echo "sources are in $WORK"
