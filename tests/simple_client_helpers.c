#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>

int
os_create_anonymous_file(off_t size)
{
    static const char template[] = "/weston-shared-XXXXXX";
    const char *path;
    char *name;
    int fd;
    int ret;

    path = getenv("XDG_RUNTIME_DIR");
    if (!path) {
        errno = ENOENT;
        return -1;
    }

    name = malloc(strlen(path) + sizeof(template));
    if (!name)
        return -1;

    strcpy(name, path);
    strcat(name, template);

    fd = mkstemp(name);
    if (fd >= 0) {
        unlink(name);
        ret = ftruncate(fd, size);
        if (ret < 0) {
            close(fd);
            fd = -1;
        }
    }

    free(name);
    return fd;
}

#ifndef HAVE_STRCHRNUL
char *
strchrnul(const char *s, int c)
{
    char *t = strchr(s, c);
    return t ? t : (char *)s + strlen(s);
}
#endif
