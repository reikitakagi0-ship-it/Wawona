/*
 * iOS Compatibility Layer for Pixman
 * Provides implementations of platform-specific functions for iOS
 */

#ifndef PIXMAN_IOS_COMPAT_H
#define PIXMAN_IOS_COMPAT_H

#ifdef __APPLE__

#include <fenv.h>
#include <math.h>
#include <stdint.h>
#include <stddef.h>

/* feenableexcept - floating point exception control */
/* iOS doesn't support floating point exceptions, provide stub */
static inline int feenableexcept(int excepts) {
   (void)excepts;
   return 0; /* Always succeed, but don't actually enable exceptions */
}

/* getisax - Solaris instruction set availability check */
/* iOS doesn't have this, provide stub that returns 0 (no extensions) */
static inline int getisax(uint32_t *array, size_t n) {
   (void)array;
   (void)n;
   return 0; /* No instruction set extensions detected */
}

#endif /* __APPLE__ */

#endif /* PIXMAN_IOS_COMPAT_H */

