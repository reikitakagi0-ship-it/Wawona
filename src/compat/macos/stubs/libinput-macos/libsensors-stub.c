/*
 * libsensors stub implementation for macOS/iOS
 * Provides minimal stub functions to satisfy linker dependencies
 */

#include <stdio.h>

// Stub functions - all no-ops
int sensors_init(void *input) { return 0; }
void sensors_cleanup(void) {}
int sensors_get_detected_chips(const void **chip, int *nr) { return 0; }
int sensors_get_features(const void *name, int *feature_nr) { return 0; }
int sensors_get_all_subfeatures(const void *name, int feature_nr, const void **subfeature) { return 0; }
double sensors_get_value(const void *name, int feature) { return 0.0; }
int sensors_set_value(const void *name, int feature, double value) { return 0; }
const char *sensors_get_label(const void *name, int feature) { return NULL; }
int sensors_get_ignored(const void *name, int feature) { return 0; }
int sensors_set_ignored(const void *name, int feature, int ignored) { return 0; }

