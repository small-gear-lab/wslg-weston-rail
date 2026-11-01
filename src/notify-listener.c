/* Stand-in for the WSLGd side of the ready notification: listen on a unix SOCK_SEQPACKET socket,
 * report the first connection, exit. Static binary, so that it runs in the WSLg system distro. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>

int main(int argc, char **argv)
{
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	struct timeval tv = { .tv_sec = 25 };
	int s, c;

	if (argc < 2 || strlen(argv[1]) >= sizeof(a.sun_path))
		return 2;
	strcpy(a.sun_path, argv[1]);
	unlink(argv[1]);
	s = socket(AF_UNIX, SOCK_SEQPACKET, 0);
	if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof(a)) < 0 || listen(s, 1) < 0) {
		perror("listener setup");
		return 1;
	}
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	printf("listening on %s\n", argv[1]);
	fflush(stdout);
	c = accept(s, NULL, NULL);
	if (c < 0) {
		puts("no connection (timeout)");
		return 1;
	}
	puts("ACCEPTED connection");
	close(c);
	return 0;
}
