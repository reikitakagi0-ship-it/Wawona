#ifndef SIGNALFD_COMPAT_H
#define SIGNALFD_COMPAT_H

#ifdef __APPLE__

#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>

/* signalfd flags */
#define SFD_CLOEXEC O_CLOEXEC
#define SFD_NONBLOCK O_NONBLOCK

/* signalfd_siginfo structure - simplified version */
struct signalfd_siginfo {
	uint32_t ssi_signo;
	int32_t ssi_errno;
	int32_t ssi_code;
	uint32_t ssi_pid;
	uint32_t ssi_uid;
	int32_t ssi_fd;
	uint32_t ssi_tid;
	uint32_t ssi_band;
	uint32_t ssi_overrun;
	uint32_t ssi_trapno;
	int32_t ssi_status;
	int64_t ssi_int;
	uint64_t ssi_ptr;
	uint64_t ssi_utime;
	uint64_t ssi_stime;
	uint64_t ssi_addr;
	uint16_t ssi_addr_lsb;
	uint16_t __pad2;
	int64_t ssi_syscall;
	uint64_t ssi_call_addr;
	uint32_t ssi_arch;
	uint8_t __pad[28];
};

/* Self-pipe trick for signalfd emulation */
struct signalfd_context {
	int pipefd[2];
	sigset_t mask;
	int fd;
};

/* Internal: get or create signalfd context for a signal */
static inline struct signalfd_context *
signalfd_get_context(int sig)
{
	static struct signalfd_context contexts[32];
	static int initialized = 0;
	
	if (!initialized) {
		for (int i = 0; i < 32; i++) {
			contexts[i].fd = -1;
			contexts[i].pipefd[0] = -1;
			contexts[i].pipefd[1] = -1;
		}
		initialized = 1;
	}
	
	/* Find or create context for this signal */
	for (int i = 0; i < 32; i++) {
		if (contexts[i].fd == -1 || sigismember(&contexts[i].mask, sig)) {
			if (contexts[i].fd == -1) {
				if (pipe(contexts[i].pipefd) < 0) {
					return NULL;
				}
				fcntl(contexts[i].pipefd[0], F_SETFD, FD_CLOEXEC);
				fcntl(contexts[i].pipefd[1], F_SETFD, FD_CLOEXEC);
				contexts[i].fd = contexts[i].pipefd[0];
				sigemptyset(&contexts[i].mask);
			}
			sigaddset(&contexts[i].mask, sig);
			return &contexts[i];
		}
	}
	
	return NULL;
}

/* Signal handler that writes to pipe */
static void
signalfd_handler(int sig)
{
	struct signalfd_context *ctx = signalfd_get_context(sig);
	if (ctx && ctx->pipefd[1] >= 0) {
		char byte = (char)sig;
		write(ctx->pipefd[1], &byte, 1);
	}
}

/* signalfd() implementation using self-pipe trick */
static inline int
signalfd(int fd, const sigset_t *mask, int flags)
{
	if (fd != -1) {
		/* Reusing existing fd not supported in this simple implementation */
		errno = EINVAL;
		return -1;
	}
	
	if (!mask) {
		errno = EINVAL;
		return -1;
	}
	
	/* Block signals first */
	sigset_t old_mask;
	sigprocmask(SIG_BLOCK, mask, &old_mask);
	
	/* Create pipe */
	int pipefd[2];
	if (pipe(pipefd) < 0) {
		return -1;
	}
	
	/* Set flags */
	if (flags & SFD_CLOEXEC) {
		fcntl(pipefd[0], F_SETFD, FD_CLOEXEC);
		fcntl(pipefd[1], F_SETFD, FD_CLOEXEC);
	}
	if (flags & SFD_NONBLOCK) {
		fcntl(pipefd[0], F_SETFL, O_NONBLOCK);
		fcntl(pipefd[1], F_SETFL, O_NONBLOCK);
	}
	
	/* Set up signal handlers for each signal in mask */
	for (int sig = 1; sig < 32; sig++) {
		if (sigismember(mask, sig)) {
			struct signalfd_context *ctx = signalfd_get_context(sig);
			if (ctx) {
				struct sigaction sa;
				sa.sa_handler = signalfd_handler;
				sigemptyset(&sa.sa_mask);
				sa.sa_flags = SA_RESTART;
				sigaction(sig, &sa, NULL);
			}
		}
	}
	
	return pipefd[0];
}

#endif /* __APPLE__ */

#endif /* SIGNALFD_COMPAT_H */

