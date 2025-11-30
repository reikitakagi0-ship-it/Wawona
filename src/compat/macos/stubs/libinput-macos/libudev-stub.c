/*
 * libudev stub implementation for macOS/iOS
 * Provides minimal stub functions to satisfy linker dependencies
 */

#include <stdio.h>
#include <stdlib.h>

// Stub types (minimal definitions)
struct udev {};
struct udev_device {};
struct udev_enumerate {};
struct udev_monitor {};
struct udev_list_entry {};

// Stub functions - all no-ops or return NULL/0
struct udev *udev_new(void) { return NULL; }
void udev_unref(struct udev *udev) {}
struct udev_device *udev_device_new_from_syspath(struct udev *udev, const char *syspath) { return NULL; }
struct udev_device *udev_device_new_from_devnum(struct udev *udev, char type, dev_t devnum) { return NULL; }
struct udev_device *udev_device_new_from_subsystem_sysname(struct udev *udev, const char *subsystem, const char *sysname) { return NULL; }
void udev_device_unref(struct udev_device *udev_device) {}
const char *udev_device_get_devnode(struct udev_device *udev_device) { return NULL; }
const char *udev_device_get_subsystem(struct udev_device *udev_device) { return NULL; }
const char *udev_device_get_syspath(struct udev_device *udev_device) { return NULL; }
const char *udev_device_get_sysname(struct udev_device *udev_device) { return NULL; }
const char *udev_device_get_property_value(struct udev_device *udev_device, const char *key) { return NULL; }
struct udev_list_entry *udev_device_get_properties_list_entry(struct udev_device *udev_device) { return NULL; }
struct udev_enumerate *udev_enumerate_new(struct udev *udev) { return NULL; }
void udev_enumerate_unref(struct udev_enumerate *udev_enumerate) {}
int udev_enumerate_add_match_subsystem(struct udev_enumerate *udev_enumerate, const char *subsystem) { return 0; }
int udev_enumerate_scan_devices(struct udev_enumerate *udev_enumerate) { return 0; }
struct udev_list_entry *udev_enumerate_get_list_entry(struct udev_enumerate *udev_enumerate) { return NULL; }
struct udev_monitor *udev_monitor_new_from_netlink(struct udev *udev, const char *name) { return NULL; }
void udev_monitor_unref(struct udev_monitor *udev_monitor) {}
int udev_monitor_filter_add_match_subsystem_devtype(struct udev_monitor *udev_monitor, const char *subsystem, const char *devtype) { return 0; }
int udev_monitor_enable_receiving(struct udev_monitor *udev_monitor) { return 0; }
int udev_monitor_get_fd(struct udev_monitor *udev_monitor) { return -1; }
struct udev_device *udev_monitor_receive_device(struct udev_monitor *udev_monitor) { return NULL; }
struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *list_entry) { return NULL; }
const char *udev_list_entry_get_name(struct udev_list_entry *list_entry) { return NULL; }

