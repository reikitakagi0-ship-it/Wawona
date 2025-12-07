#include "logging.h"
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <errno.h>

FILE *compositor_log_file = NULL;
FILE *client_log_file = NULL;

void init_compositor_logging(void)
{
    // Ensure logs directory exists
    struct stat st = {0};
    if (stat("logs", &st) == -1) {
        if (mkdir("logs", 0755) == -1 && errno != EEXIST) {
            perror("Failed to create logs directory");
        }
    }

    compositor_log_file = fopen("logs/wawona_compositor.log", "w");
    if (!compositor_log_file) {
        perror("Failed to open compositor log file");
    }
}

void init_client_logging(void)
{
    // Ensure logs directory exists (redundant if init_compositor_logging called first, but safe)
    struct stat st = {0};
    if (stat("logs", &st) == -1) {
        if (mkdir("logs", 0755) == -1 && errno != EEXIST) {
            perror("Failed to create logs directory");
        }
    }

    client_log_file = fopen("logs/wawona_client.log", "w");
    if (!client_log_file) {
        perror("Failed to open client log file");
    }
}

void log_printf(const char *prefix, const char *format, ...)
{
    va_list args;
    time_t now;
    char time_str[64];
    
    struct tm *tm_info;
    
    time(&now);
    tm_info = localtime(&now);
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);
    
    // Print to stdout
    printf("[%s] [%s] ", time_str, prefix);
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    printf("\n");
    
    // Print to log file if open
    if (compositor_log_file) {
        fprintf(compositor_log_file, "[%s] [%s] ", time_str, prefix);
        va_start(args, format);
        vfprintf(compositor_log_file, format, args);
        va_end(args);
        fprintf(compositor_log_file, "\n");
        fflush(compositor_log_file);
    }
}

void log_fflush(void)
{
    fflush(stdout);
    if (compositor_log_file) fflush(compositor_log_file);
    if (client_log_file) fflush(client_log_file);
}

void cleanup_logging(void)
{
    if (compositor_log_file) {
        fclose(compositor_log_file);
        compositor_log_file = NULL;
    }
    if (client_log_file) {
        fclose(client_log_file);
        client_log_file = NULL;
    }
}
