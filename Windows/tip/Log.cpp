#include "Log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>

namespace aio {

namespace {

INIT_ONCE g_logOnce = INIT_ONCE_STATIC_INIT;
HANDLE g_logFile = INVALID_HANDLE_VALUE;

BOOL CALLBACK OpenLog(PINIT_ONCE, PVOID, PVOID*) {
    wchar_t path[MAX_PATH];
    const DWORD n = GetEnvironmentVariableW(L"AIO_TIP_LOG", path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return TRUE;
    // Appends (each write is atomic), shared, so several processes can log to one file.
    g_logFile = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    return TRUE;
}

} // namespace

bool LogEnabled() noexcept {
    InitOnceExecuteOnce(&g_logOnce, OpenLog, nullptr, nullptr);
    return g_logFile != INVALID_HANDLE_VALUE;
}

void Log(const char* format, ...) noexcept {
#ifndef _DEBUG
    if (!LogEnabled()) return;
#endif
    char line[1024];
    SYSTEMTIME st;
    GetLocalTime(&st);
    int n = _snprintf_s(line, sizeof line, _TRUNCATE, "%02u:%02u:%02u.%03u %5lu %5lu tip: ", st.wHour, st.wMinute,
                        st.wSecond, st.wMilliseconds, GetCurrentProcessId(), GetCurrentThreadId());
    if (n < 0) n = 0;
    va_list args;
    va_start(args, format);
    int m = _vsnprintf_s(line + n, sizeof line - n - 2, _TRUNCATE, format, args);
    va_end(args);
    if (m < 0) m = static_cast<int>(strlen(line + n));
    n += m;
    line[n++] = '\r';
    line[n++] = '\n';
    line[n] = '\0';
#ifdef _DEBUG
    OutputDebugStringA(line);
    if (!LogEnabled()) return;
#endif
    DWORD written = 0;
    WriteFile(g_logFile, line, static_cast<DWORD>(n), &written, nullptr);
}

} // namespace aio
