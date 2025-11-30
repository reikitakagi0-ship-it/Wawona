/*
 * libelf stub header for macOS/iOS
 * ELF file manipulation is Linux-specific and not needed on macOS/iOS
 */

#ifndef LIBELF_H
#define LIBELF_H

#ifdef __cplusplus
extern "C" {
#endif

// Minimal stub - ELF is not used on macOS/iOS (uses Mach-O instead)
typedef void* Elf;

#ifdef __cplusplus
}
#endif

#endif // LIBELF_H

