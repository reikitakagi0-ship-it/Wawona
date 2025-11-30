#include <stdint.h>
#include <stddef.h>

// Minimal libevdev stub for macOS
// These functions are stubs that return safe defaults

struct input_event {
    uint64_t time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

struct libevdev {
    int dummy;
};

struct libevdev* libevdev_new(void) { return NULL; }
void libevdev_free(struct libevdev *dev) { (void)dev; }
int libevdev_set_fd(struct libevdev *dev, int fd) { (void)dev; (void)fd; return 0; }
int libevdev_get_fd(const struct libevdev *dev) { (void)dev; return -1; }
int libevdev_next_event(struct libevdev *dev, unsigned int flags, struct input_event *ev) { (void)dev; (void)flags; (void)ev; return -1; }
const char* libevdev_get_name(const struct libevdev *dev) { (void)dev; return "macOS Input Device"; }
int libevdev_has_event_type(const struct libevdev *dev, unsigned int type) { (void)dev; (void)type; return 0; }
int libevdev_has_event_code(const struct libevdev *dev, unsigned int type, unsigned int code) { (void)dev; (void)type; (void)code; return 0; }
