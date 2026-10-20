// A diagnostic log, off unless the environment variable AIO_TIP_LOG names a file to append to.
//
// §8: it records types, ids, sizes and states, never what anyone typed. Callers pass no document text, no key text
// and no frame bodies.

#pragma once

namespace aio {

// printf-style. Never throws.
void Log(const char* format, ...) noexcept;

bool LogEnabled() noexcept;

} // namespace aio
