#!/bin/sh
# Run as root in the WSLg system distro. Starts msrdc.exe the way WSLGd does (same arguments, same environment),
# for the case where WSLGd gave up restarting it ("exited more than 10 times in 60 seconds, not starting it again").
# Only does that: it does not touch Weston.
set -u
WSLGD=$(pgrep -x WSLGd | head -1)
[ -n "$WSLGD" ] || { echo "WSLGd is not running"; exit 1; }
if pgrep -f 'msrdc.exe /wslg' >/dev/null 2>&1; then echo "msrdc is already running:"; pgrep -af 'msrdc.exe /wslg' | cut -c1-100; exit 1; fi
VM=$(tr '\0' '\n' </proc/$WSLGD/environ | sed -n 's/^WSL2_VM_ID=//p')
[ -n "$VM" ] || { echo "WSL2_VM_ID not found in WSLGd's environment"; exit 1; }
echo "VM id: $VM"
# the environment of WSLGd is passed to msrdc as it is; xargs hands each NAME=VALUE entry over as one argument
setsid -f nohup xargs -0 -a /proc/$WSLGD/environ sh -c 'exec env -i "$@" "/mnt/c/Program Files/WSL/msrdc.exe" /wslg /silent "/v:'"$VM"'" "/hvsocketserviceid:00000001-FACB-11E6-BD58-64006A7986D3" "/plugin:WSLDVC_PACKAGE" "/wslgsharedmemorypath:WSL\\'"$VM"'\\wslg" "C:\\Program Files\\WSL\\wslg.rdp"' sh >/tmp/start-msrdc.out 2>&1 </dev/null
sleep 3
echo "started; processes:"; pgrep -af 'msrdc.exe' | cut -c1-120
