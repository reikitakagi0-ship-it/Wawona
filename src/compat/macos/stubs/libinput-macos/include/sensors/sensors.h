/*
 * libsensors stub header for macOS/iOS
 * libsensors is a Linux-only library for hardware sensor access
 * This provides minimal stub definitions for compatibility
 */

#ifndef SENSORS_SENSORS_H
#define SENSORS_SENSORS_H

// Stub types and constants
typedef struct sensors_chip_name {
    const char *prefix;
    int bus;
    int addr;
    const char *path;
} sensors_chip_name;

typedef struct sensors_subfeature {
    int number;
    const char *name;
    int type;
    int mapping;
    int flags;
} sensors_subfeature;

typedef struct sensors_feature {
    int number;
    const char *name;
    int type;
} sensors_feature;

// Stub function declarations (all no-ops)
int sensors_init(FILE *input);
void sensors_cleanup(void);
int sensors_get_detected_chips(const sensors_chip_name **chip, int *nr);
int sensors_get_features(const sensors_chip_name *name, int *feature_nr);
int sensors_get_all_subfeatures(const sensors_chip_name *name, int feature_nr, const sensors_subfeature **subfeature);
double sensors_get_value(const sensors_chip_name *name, int feature);
int sensors_set_value(const sensors_chip_name *name, int feature, double value);
const char *sensors_get_label(const sensors_chip_name *name, int feature);
int sensors_get_ignored(const sensors_chip_name *name, int feature);
int sensors_set_ignored(const sensors_chip_name *name, int feature, int ignored);

// Feature types (stub values)
#define SENSORS_FEATURE_IN         0x0001
#define SENSORS_FEATURE_FAN        0x0002
#define SENSORS_FEATURE_TEMP       0x0003
#define SENSORS_FEATURE_POWER      0x0004
#define SENSORS_FEATURE_ENERGY     0x0005
#define SENSORS_FEATURE_CURR       0x0006
#define SENSORS_FEATURE_HUMIDITY   0x0007
#define SENSORS_FEATURE_MAX_MAIN   0x00ff
#define SENSORS_FEATURE_VID        0x0100
#define SENSORS_FEATURE_INTRUSION  0x0200
#define SENSORS_FEATURE_MAX_OTHER  0xffff

// Subfeature types
#define SENSORS_SUBFEATURE_IN_INPUT        0x0001
#define SENSORS_SUBFEATURE_FAN_INPUT       0x0002
#define SENSORS_SUBFEATURE_TEMP_INPUT     0x0003
#define SENSORS_SUBFEATURE_POWER_INPUT    0x0004
#define SENSORS_SUBFEATURE_ENERGY_INPUT  0x0005
#define SENSORS_SUBFEATURE_CURR_INPUT    0x0006
#define SENSORS_SUBFEATURE_HUMIDITY_INPUT 0x0007

#endif // SENSORS_SENSORS_H

