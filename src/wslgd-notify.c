/*
 * wslgd-notify.so -- stand-in for the Weston module that WSLg's WSLGd waits for.
 *
 * WSLGd listens on the unix socket named by $WSLGD_NOTIFY_SOCKET and does not start the Windows
 * side (msrdc.exe) until something connects (SetupReadyNotify / WaitForReadyNotify). That happens when
 * WSLg starts; when Weston is restarted later the socket does not exist any more.
 *
 * The original module does one thing in wet_module_init(): connect() to that socket (AF_UNIX,
 * SOCK_SEQPACKET), log, close. Nothing is sent. Its return values (from the disassembly):
 *   - $WSLGD_NOTIFY_SOCKET not set      -> log, return 0
 *   - socket() fails                    -> log, return -1
 *   - connect() fails (e.g. no socket)  -> log, return 0   <- a restarted Weston must keep running
 *   - connect() succeeds                -> log, return 0
 * This does the same. Written from the observed behaviour of the original, not from its source.
 */
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <libweston/libweston.h>

WL_EXPORT int
wet_module_init(struct weston_compositor *compositor, int *argc, char *argv[])
{
	struct sockaddr_un addr;
	const char *path = getenv("WSLGD_NOTIFY_SOCKET");
	int fd, len;

	(void)compositor; (void)argc; (void)argv;

	if (!path) {
		weston_log("%s: socket path is not specified\n", __func__);
		return 0;
	}

	fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
	if (fd < 0) {
		weston_log("%s: socket failed\n", __func__);
		return -1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	len = snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
	if (len < 0)
		len = 0;
	else if ((size_t)len >= sizeof(addr.sun_path))
		len = sizeof(addr.sun_path) - 1;

	if (connect(fd, (struct sockaddr *)&addr, offsetof(struct sockaddr_un, sun_path) + len + 1) < 0)
		weston_log("%s: connect(%s) failed %s\n", __func__, path, strerror(errno));
	else
		weston_log("%s: socket connected\n", __func__);

	close(fd);
	return 0;
}
