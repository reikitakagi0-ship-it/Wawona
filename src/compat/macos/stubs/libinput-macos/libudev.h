#ifndef LIBUDEV_H
#define LIBUDEV_H

// macOS stub header for libudev
// This is a minimal stub to allow compilation on macOS

typedef struct udev udev;
typedef struct udev_device udev_device;
typedef struct udev_enumerate udev_enumerate;
typedef struct udev_list_entry udev_list_entry;
typedef struct udev_monitor udev_monitor;

struct udev *udev_new(void);
void udev_unref(struct udev *udev);
struct udev_device *udev_device_new_from_syspath(struct udev *udev, const char *syspath);
void udev_device_unref(struct udev_device *udev_device);
const char *udev_device_get_syspath(struct udev_device *udev_device);
const char *udev_device_get_subsystem(struct udev_device *udev_device);
const char *udev_device_get_devtype(struct udev_device *udev_device);
const char *udev_device_get_sysname(struct udev_device *udev_device);
const char *udev_device_get_sysattr_value(struct udev_device *udev_device, const char *sysattr);
struct udev_list_entry *udev_device_get_properties_list_entry(struct udev_device *udev_device);
const char *udev_list_entry_get_name(struct udev_list_entry *list_entry);
const char *udev_list_entry_get_value(struct udev_list_entry *list_entry);
struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *list_entry);

#endif // LIBUDEV_H
