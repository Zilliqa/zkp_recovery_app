// Baked launch fix (part 1 of 2) for Barretenberg's ~1MB initial-exec TLS.
//
// Barretenberg (pulled in via the Noir prover) carries ~1MB of initial-exec
// thread-local storage. Two things break because of it:
//   (1) dlopen'ing the lib late fails with "cannot allocate memory in static
//       TLS block" -> fixed by startup-loading the lib (see linux/CMakeLists.txt).
//   (2) once that TLS inflates every thread's minimum size, Dart/engine threads
//       that request a small stack fail pthread_create with EINVAL(22).
//
// This file fixes (2): it defines pthread_create in the EXECUTABLE itself, so it
// wins global symbol resolution and intercepts every thread the engine, Dart VM,
// GTK and Barretenberg create, bumping any sub-4MB stack request up to 4MB. The
// real pthread_create is reached via RTLD_NEXT. No LD_PRELOAD, no wrapper.
#ifndef _GNU_SOURCE
#define _GNU_SOURCE  // for RTLD_NEXT (g++ usually predefines this already)
#endif
#include <pthread.h>
#include <dlfcn.h>
#include <stddef.h>

extern "C" int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                              void *(*start_routine)(void *), void *arg) {
  typedef int (*create_fn)(pthread_t *, const pthread_attr_t *,
                           void *(*)(void *), void *);
  static create_fn real_create = NULL;
  if (real_create == NULL) {
    real_create = reinterpret_cast<create_fn>(dlsym(RTLD_NEXT, "pthread_create"));
  }

  pthread_attr_t local_attr;
  int own_attr = 0;
  if (attr != NULL) {
    local_attr = *attr;
  } else {
    pthread_attr_init(&local_attr);
    own_attr = 1;
  }

  size_t stack_size = 0;
  pthread_attr_getstacksize(&local_attr, &stack_size);
  const size_t kMinStack = 4UL << 20;  // 4 MB
  if (stack_size < kMinStack) {
    pthread_attr_setstacksize(&local_attr, kMinStack);
  }

  int rc = real_create(thread, &local_attr, start_routine, arg);
  if (own_attr) {
    pthread_attr_destroy(&local_attr);
  }
  return rc;
}
