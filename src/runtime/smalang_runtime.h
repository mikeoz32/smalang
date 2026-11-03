#ifndef SMALANG_RUNTIME_H
#define SMALANG_RUNTIME_H

#include <stddef.h>
#include <stdint.h>
#include <unwind.h>

enum smalang_exception_kind {
  SMALANG_EXCEPTION_DIVISION_BY_ZERO = 1,
};

struct smalang_exception;

struct smalang_exception *smalang_exception_new(enum smalang_exception_kind kind);
enum smalang_exception_kind smalang_exception_kind(const struct smalang_exception *exception);
size_t smalang_exception_frame_count(const struct smalang_exception *exception);
uintptr_t smalang_exception_frame_at(const struct smalang_exception *exception, size_t index);
int smalang_exception_suppress(struct smalang_exception *active, struct smalang_exception *previous);
size_t smalang_exception_suppressed_count(const struct smalang_exception *exception);
_Unwind_Reason_Code smalang_exception_raise(struct smalang_exception *exception);
_Noreturn void smalang_exception_resume(struct smalang_exception *exception);
void smalang_exception_delete(struct smalang_exception *exception);

#endif
