/* Sleep in the kernel until the compositor exits, then stop its owned units. */
#define _GNU_SOURCE
#include <sys/syscall.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <stdlib.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 3 || !argv[1][0] || !argv[2][0] ||
        strspn(argv[1], "0123456789") != strlen(argv[1]) ||
        strspn(argv[2], "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-") != strlen(argv[2])) return 2;
    errno = 0;
    long pid = strtol(argv[1], NULL, 10);
    if (errno != 0 || pid <= 0 || pid > INT_MAX) return 2;
    int fd = syscall(SYS_pidfd_open, (int)pid, 0);
    if (fd < 0 && errno != ESRCH) { perror("pidfd_open"); return 1; }
    if (fd >= 0) {
        struct pollfd p = { .fd = fd, .events = POLLIN };
        while (poll(&p, 1, -1) < 0) {
            if (errno != EINTR) { close(fd); return 1; }
        }
        close(fd);
    }
    char pattern[512];
    if (snprintf(pattern, sizeof pattern, "%s-*", argv[2]) >= (int)sizeof pattern) return 2;
    execlp("systemctl", "systemctl", "--user", "stop", pattern, NULL);
    perror("systemctl"); return 1;
}
