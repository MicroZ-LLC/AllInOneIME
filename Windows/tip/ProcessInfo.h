// Who this process is, and whether its DLL may talk to the engine at all (§2.1, §8).

#pragma once

#include <windows.h>

#include <string>

namespace aio {

struct ProcessInfo {
    std::wstring userSid;       // "S-1-5-21-…-1001"
    DWORD sessionId = 0;
    DWORD integrity = 0;        // SECURITY_MANDATORY_*_RID
    bool appContainer = false;
    bool systemAccount = false; // SYSTEM, LocalService or NetworkService
    bool service = false;       // in the SERVICE group, or in session 0 (where only services and their children run)
    std::wstring windowStation;
    std::string exeName;        // UTF-8, lowercase: "notepad.exe"
    std::string app;            // UTF-8: "win:<exe>", or "win:<AUMID>" for a packaged app
};

// Worked out once per process.
const ProcessInfo& CurrentProcess() noexcept;

// The name of the calling thread's desktop: "Default", "Winlogon", "Screen-saver" ….
std::wstring ThreadDesktopName();

// False, with the reason, where the DLL must stay passive: SYSTEM and the service accounts, services, session 0, a
// window station other than WinSta0, and any desktop other than Default (§2.1). Checked on the calling thread.
bool MayConnect(const char** why);

// `\\.\pipe\AllInOneIME-<UserSID>-v1`
std::wstring PipeName(const std::wstring& userSid);

// `Local\AllInOneIME-Engine-<SID>`, the engine's single-instance mutex.
std::wstring EngineMutexName(const std::wstring& userSid);

// §2.1, the server check, on a connected pipe: the server is in this session, the pipe's owner is this user, and the
// server process runs as this user at medium integrity or higher, outside an AppContainer. See README.md for how the
// label check of the spec is done.
bool VerifyServer(HANDLE pipe, const char** why);

// The integrity level of the token, as SECURITY_MANDATORY_*_RID; 0 if it can't be read.
DWORD TokenIntegrity(HANDLE token);

// The token's user as a string SID; empty if it can't be read.
std::wstring TokenUserSid(HANDLE token);

} // namespace aio
