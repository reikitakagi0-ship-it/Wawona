#include <stdint.h>
#include <stddef.h>

// Minimal mtdev stub for macOS
struct input_event {
    uint64_t time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

struct mtdev {
    int dummy;
};

struct mtdev* mtdev_open(const char *path, int flags) { (void)path; (void)flags; return NULL; }
void mtdev_close(struct mtdev *mtdev) { (void)mtdev; }
int mtdev_get(struct mtdev *mtdev, struct input_event *ev, int maxev) { (void)mtdev; (void)ev; (void)maxev; return 0; }
