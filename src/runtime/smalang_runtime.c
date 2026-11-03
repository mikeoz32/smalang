#include "smalang_runtime.h"

#include <stdlib.h>

#define SMALANG_EXCEPTION_CLASS UINT64_C(0x534d414c414e4701)
#define SMALANG_MAX_TRACE_FRAMES 64

struct smalang_exception {
  struct _Unwind_Exception unwind_header;
  enum smalang_exception_kind kind;
  struct smalang_exception *suppressed;
  size_t frame_count;
  uintptr_t frames[SMALANG_MAX_TRACE_FRAMES];
};

static void smalang_exception_destroy_chain(struct smalang_exception *exception);

static void smalang_exception_cleanup(_Unwind_Reason_Code reason,
                                      struct _Unwind_Exception *unwind_header) {
  (void)reason;
  smalang_exception_destroy_chain((struct smalang_exception *)unwind_header);
}

static void smalang_exception_destroy_chain(struct smalang_exception *exception) {
  while (exception != NULL) {
    struct smalang_exception *suppressed = exception->suppressed;
    free(exception);
    exception = suppressed;
  }
}

struct smalang_exception *smalang_exception_new(enum smalang_exception_kind kind) {
  if (kind != SMALANG_EXCEPTION_DIVISION_BY_ZERO) {
    return NULL;
  }

  struct smalang_exception *exception = calloc(1, sizeof(*exception));
  if (exception == NULL) {
    return NULL;
  }

  exception->unwind_header.exception_class = SMALANG_EXCEPTION_CLASS;
  exception->unwind_header.exception_cleanup = smalang_exception_cleanup;
  exception->kind = kind;
  return exception;
}

enum smalang_exception_kind smalang_exception_kind(const struct smalang_exception *exception) {
  return exception == NULL ? 0 : exception->kind;
}

size_t smalang_exception_frame_count(const struct smalang_exception *exception) {
  return exception == NULL ? 0 : exception->frame_count;
}

uintptr_t smalang_exception_frame_at(const struct smalang_exception *exception, size_t index) {
  if (exception == NULL || index >= exception->frame_count) {
    return 0;
  }
  return exception->frames[index];
}

int smalang_exception_suppress(struct smalang_exception *active,
                               struct smalang_exception *previous) {
  if (active == NULL || previous == NULL || active == previous) {
    return 0;
  }

  struct smalang_exception *tail = active;
  while (tail->suppressed != NULL) {
    if (tail->suppressed == previous) {
      return 0;
    }
    tail = tail->suppressed;
  }

  for (struct smalang_exception *candidate = previous; candidate != NULL;
       candidate = candidate->suppressed) {
    if (candidate == active) {
      return 0;
    }
  }

  tail->suppressed = previous;
  return 1;
}

size_t smalang_exception_suppressed_count(const struct smalang_exception *exception) {
  size_t count = 0;
  if (exception == NULL) {
    return 0;
  }

  for (const struct smalang_exception *suppressed = exception->suppressed;
       suppressed != NULL; suppressed = suppressed->suppressed) {
    count++;
  }
  return count;
}

static _Unwind_Reason_Code smalang_capture_frame(struct _Unwind_Context *context,
                                                  void *argument) {
  struct smalang_exception *exception = argument;
  uintptr_t instruction_pointer = (uintptr_t)_Unwind_GetIP(context);
  if (instruction_pointer != 0 && exception->frame_count < SMALANG_MAX_TRACE_FRAMES) {
    exception->frames[exception->frame_count++] = instruction_pointer;
  }

  return exception->frame_count == SMALANG_MAX_TRACE_FRAMES ? _URC_END_OF_STACK
                                                             : _URC_NO_REASON;
}

_Unwind_Reason_Code smalang_exception_raise(struct smalang_exception *exception) {
  if (exception == NULL) {
    return _URC_FATAL_PHASE1_ERROR;
  }

  exception->frame_count = 0;
  _Unwind_Backtrace(smalang_capture_frame, exception);
  return _Unwind_RaiseException(&exception->unwind_header);
}

_Noreturn void smalang_exception_resume(struct smalang_exception *exception) {
  if (exception == NULL) {
    abort();
  }
  _Unwind_Resume(&exception->unwind_header);
  abort();
}

void smalang_exception_delete(struct smalang_exception *exception) {
  if (exception != NULL) {
    _Unwind_DeleteException(&exception->unwind_header);
  }
}
