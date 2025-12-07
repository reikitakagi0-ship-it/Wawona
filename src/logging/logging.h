#pragma once

#include <stdio.h>
#include <stdarg.h>

// Log file handles
extern FILE *compositor_log_file;
extern FILE *client_log_file;

// Initialize logging
void init_compositor_logging(void);
void init_client_logging(void);

// Logging function that writes to both stdout and file
void log_printf(const char *prefix, const char *format, ...);
void log_fflush(void);

// Cleanup
void cleanup_logging(void);

