#include <stdint.h>
#include <stddef.h>

// Minimal libudev stub for macOS
struct udev {
    int dummy;
};

struct udev* udev_new(void) { return NULL; }
void udev_unref(struct udev *udev) { (void)udev; }
struct udev_device* udev_device_new_from_syspath(struct udev *udev, const char *syspath) { (void)udev; (void)syspath; return NULL; }
void udev_device_unref(struct udev_device *device) { (void)device; }
const char* udev_device_get_devnode(struct udev_device *device) { (void)device; return NULL; }
