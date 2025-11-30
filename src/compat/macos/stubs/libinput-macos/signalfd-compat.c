#ifdef __APPLE__

#include "signalfd-compat.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/socket.h>

/* Maximum number of signalfd contexts */
#define MAX_SIGNALFD_CONTEXTS 32

/* signalfd context structure */
struct signalfd_context {
	int pipefd[2];
	sigset_t mask;
	int fd;
	int refcount;
	struct signalfd_context *next;
};

/* Global list of signalfd contexts */
static struct signalfd_context *signalfd_contexts = NULL;
static pthread_mutex_t signalfd_mutex = PTHREAD_MUTEX_INITIALIZER;

/* Signal handler that writes signal number to pipe */
static void
signalfd_signal_handler(int sig)
{
	pthread_mutex_lock(&signalfd_mutex);
	
	struct signalfd_context *ctx = signalfd_contexts;
	while (ctx) {
		if (sigismember(&ctx->mask, sig) && ctx->pipefd[1] >= 0) {
			char byte = (char)sig;
			write(ctx->pipefd[1], &byte, 1);
		}
		ctx = ctx->next;
	}
	
	pthread_mutex_unlock(&signalfd_mutex);
}

/* Find or create a signalfd context */
static struct signalfd_context *
signalfd_find_or_create_context(const sigset_t *mask)
{
	pthread_mutex_lock(&signalfd_mutex);
	
	/* Try to find existing context with matching mask */
	struct signalfd_context *ctx = signalfd_contexts;
	while (ctx) {
		if (sigequal(&ctx->mask, mask)) {
			ctx->refcount++;
			pthread_mutex_unlock(&signalfd_mutex);
			return ctx;
		}
		ctx = ctx->next;
	}
	
	/* Create new context */
	ctx = calloc(1, sizeof(struct signalfd_context));
	if (!ctx) {
		pthread_mutex_unlock(&signalfd_mutex);
		return NULL;
	}
	
	if (pipe(ctx->pipefd) < 0) {
		free(ctx);
		pthread_mutex_unlock(&signalfd_mutex);
		return NULL;
	}
	
	/* Set flags */
	fcntl(ctx->pipefd[0], F_SETFD, FD_CLOEXEC);
	fcntl(ctx->pipefd[1], F_SETFD, FD_CLOEXEC);
	fcntl(ctx->pipefd[0], F_SETFL, O_NONBLOCK);
	fcntl(ctx->pipefd[1], F_SETFL, O_NONBLOCK);
	
	ctx->fd = ctx->pipefd[0];
	ctx->mask = *mask;
	ctx->refcount = 1;
	ctx->next = signalfd_contexts;
	signalfd_contexts = ctx;
	
	/* Set up signal handlers for each signal in mask */
	for (int sig = 1; sig < 32; sig++) {
		if (sigismember(mask, sig)) {
			struct sigaction sa;
			sa.sa_handler = signalfd_signal_handler;
			sigemptyset(&sa.sa_mask);
			sa.sa_flags = SA_RESTART;
			sigaction(sig, &sa, NULL);
		}
	}
	
	/* Block signals */
	sigset_t old_mask;
	sigprocmask(SIG_BLOCK, mask, &old_mask);
	
	pthread_mutex_unlock(&signalfd_mutex);
	return ctx;
}

/* signalfd() implementation */
int
signalfd(int fd, const sigset_t *mask, int flags)
{
	if (fd != -1) {
		/* Reusing existing fd - find context and increment refcount */
		pthread_mutex_lock(&signalfd_mutex);
		struct signalfd_context *ctx = signalfd_contexts;
		while (ctx) {
			if (ctx->fd == fd) {
				ctx->refcount++;
				pthread_mutex_unlock(&signalfd_mutex);
				return fd;
			}
			ctx = ctx->next;
		}
		pthread_mutex_unlock(&signalfd_mutex);
		errno = EINVAL;
		return -1;
	}
	
	if (!mask) {
		errno = EINVAL;
		return -1;
	}
	
	struct signalfd_context *ctx = signalfd_find_or_create_context(mask);
	if (!ctx) {
		return -1;
	}
	
	/* Apply flags */
	if (flags & SFD_CLOEXEC) {
		fcntl(ctx->pipefd[0], F_SETFD, FD_CLOEXEC);
		fcntl(ctx->pipefd[1], F_SETFD, FD_CLOEXEC);
	}
	if (flags & SFD_NONBLOCK) {
		fcntl(ctx->pipefd[0], F_SETFL, O_NONBLOCK);
		fcntl(ctx->pipefd[1], F_SETFL, O_NONBLOCK);
	}
	
	return ctx->fd;
}

/* Helper function to check if sigsets are equal */
static int
sigequal(const sigset_t *set1, const sigset_t *set2)
{
	for (int i = 0; i < _SIGSET_NWORDS; i++) {
		if (set1->__val[i] != set2->__val[i]) {
			return 0;
		}
	}
	return 1;
}

#endif /* __APPLE__ */

