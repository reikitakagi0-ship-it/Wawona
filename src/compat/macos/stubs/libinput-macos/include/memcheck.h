/*
 * Valgrind memcheck stub header for macOS/iOS
 * Valgrind is a Linux-only development tool
 * This provides no-op macros for all Valgrind memory checking functions
 */

#ifndef MEMCHECK_H
#define MEMCHECK_H

// Memory checking macros - all no-ops on macOS/iOS
// These must be function-like macros that can be called
#define VALGRIND_CHECK_MEM_IS_DEFINED(addr, size) ((void)0)
#define VALGRIND_CHECK_MEM_IS_ADDRESSABLE(addr, size) ((void)0)
#define VALGRIND_CHECK_VALUE_IS_DEFINED(value) ((void)0)
#define VALGRIND_MAKE_MEM_DEFINED(addr, size) ((void)0)
#define VALGRIND_MAKE_MEM_UNDEFINED(addr, size) ((void)0)
#define VALGRIND_MAKE_MEM_NOACCESS(addr, size) ((void)0)
#define VALGRIND_MAKE_MEM_READABLE(addr, size) ((void)0)
#define VALGRIND_MAKE_MEM_WRITABLE(addr, size) ((void)0)
#define VALGRIND_DISCARD(addr, size) ((void)0)
#define VALGRIND_CHECK_READABLE(addr, size) ((void)0)
#define VALGRIND_CHECK_WRITABLE(addr, size) ((void)0)

// Memory pool macros
#define VALGRIND_CREATE_MEMPOOL(pool, rzB, is_zeroed) ((void)0)
#define VALGRIND_DESTROY_MEMPOOL(pool) ((void)0)
#define VALGRIND_MEMPOOL_ALLOC(pool, addr, size) ((void)0)
#define VALGRIND_MEMPOOL_FREE(pool, addr) ((void)0)
#define VALGRIND_MEMPOOL_CHANGE(pool, addrA, addrB, size) ((void)0)
#define VALGRIND_MEMPOOL_EXISTS(pool) 0
#define VALGRIND_MOVE_MEMPOOL(poolA, poolB) ((void)0)
#define VALGRIND_MEMPOOL_TRIM(pool, addr, size) ((void)0)

// Malloc-like block macros
#define VALGRIND_MALLOCLIKE_BLOCK(addr, sizeB, rzB, is_zeroed) ((void)0)
#define VALGRIND_FREELIKE_BLOCK(addr, rzB) ((void)0)
#define VALGRIND_RESIZE_INPLACE_BLOCK(addr, oldSizeB, newSizeB, rzB) ((void)0)

// Stack macros
#define VALGRIND_STACK_REGISTER(start, end) 0
#define VALGRIND_STACK_DEREGISTER(id) ((void)0)
#define VALGRIND_STACK_CHANGE(id, start, end) ((void)0)

// Address space macros
#define VALGRIND_MAKE_MEM_DEFINED_IF_ADDRESSABLE(addr, size) ((void)0)

#endif // MEMCHECK_H
