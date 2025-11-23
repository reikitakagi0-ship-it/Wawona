#include "logging.h"
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

FILE *compositor_log_file = NULL;
FILE *client_log_file = NULL;

void init_compositor_logging(void) {
    // Open log file for compositor
    const char *log_path = "/tmp/compositor-run.log";
    compositor_log_file = fopen(log_path, "a"); // Append mode
    if (compositor_log_file) {
        // Write header if file is new or empty
        fseek(compositor_log_file, 0, SEEK_END);
        if (ftell(compositor_log_file) == 0) {
            fprintf(compositor_log_file, "=== Compositor Log Started ===\n");
            fflush(compositor_log_file);
        }
    } else {
        // Fallback to stderr if file can't be opened
        fprintf(stderr, "Warning: Could not open log file %s, logging to stderr\n", log_path);
    }
}

void init_client_logging(void) {
    // Logging now goes to stdout/stderr which is redirected to /tmp/client-run.log or /tmp/input-client-run.log
    // No separate log file needed
    client_log_file = NULL;
}

void log_printf(const char *prefix, const char *format, ...) {
    va_list args;
    
    // Determine which log file to use (compositor or client)
    FILE *log_file = compositor_log_file ? compositor_log_file : client_log_file;
    
    if (log_file) {
        // Log to file (compositor or client log file)
        if (prefix) {
            fprintf(log_file, "%s", prefix);
        }
        va_start(args, format);
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wformat-nonliteral"
        vfprintf(log_file, format, args);
        #pragma clang diagnostic pop
        va_end(args);
        fflush(log_file);
    } else {
        // Fallback to stderr if no log file is set
        if (prefix) {
            fprintf(stderr, "%s", prefix);
        }
        va_start(args, format);
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wformat-nonliteral"
        vfprintf(stderr, format, args);
        #pragma clang diagnostic pop
        va_end(args);
        fflush(stderr);
    }
}

void log_fflush(void) {
    fflush(stdout);
    if (compositor_log_file) fflush(compositor_log_file);
    if (client_log_file) fflush(client_log_file);
}

void cleanup_logging(void) {
    if (compositor_log_file) {
        fprintf(compositor_log_file, "\n=== Compositor Log Ended ===\n\n");
        fclose(compositor_log_file);
        compositor_log_file = NULL;
    }
    if (client_log_file) {
        fprintf(client_log_file, "\n=== Client Log Ended ===\n\n");
        fclose(client_log_file);
        client_log_file = NULL;
    }
}

