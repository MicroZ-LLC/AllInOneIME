#include "PipeClient.h"

#include <algorithm>
#include <atomic>
#include <deque>
#include <iterator>
#include <mutex>

#include "Globals.h"
#include "Log.h"
#include "ProcessInfo.h"

namespace aio {

namespace {

constexpr UINT kMsgInbox = WM_APP + 1;
constexpr UINT_PTR kTimerKeepalive = 1;
constexpr DWORD kHandshakeTimeoutMs = 2000;
constexpr DWORD kNotificationWriteTimeoutMs = 50;
constexpr ULONGLONG kKeepaliveIdleMs = 15000;
constexpr ULONGLONG kPongTimeoutMs = 2000;
// §2.5: 0, 250 ms, 1 s, 2 s, then every 5 s.
constexpr DWORD kBackoffMs[] = {0, 250, 1000, 2000, 5000};
constexpr size_t kLastBackoff = std::size(kBackoffMs) - 1;
constexpr wchar_t kWindowClass[] = L"AllInOneIME.TipPipe";

std::mutex g_classMutex;
int g_classUsers = 0;

enum class Io { ok, timeout, stopped, dropped, broken, tooLarge };

const char* IoName(Io r) {
    switch (r) {
    case Io::ok: return "ok";
    case Io::timeout: return "timeout";
    case Io::stopped: return "stopped";
    case Io::dropped: return "dropped";
    case Io::broken: return "broken pipe";
    case Io::tooLarge: return "tooLarge";
    }
    return "?";
}

} // namespace

struct Inbound {
    enum class Kind { frame, connected, disconnected } kind = Kind::frame;
    uint64_t generation = 0;
    uint64_t seq = 0;
    wire::EngineMessage message;
};

struct PipeClient::Shared {
    std::mutex m; // guards everything below up to `writeMutex`
    HWND wnd = nullptr;
    bool postPending = false;
    std::deque<Inbound> inbox;
    uint64_t nextSeq = 1;
    uint64_t generation = 0;
    bool connected = false;
    uint32_t waitId = 0; // the request the TSF thread waits on
    bool waitDone = false;
    bool waitFailed = false;
    wire::EngineMessage waitResponse;
    uint64_t waitSeq = 0;
    DWORD retryAfterMs = 0; // from `bye`

    // Held while a frame is written, and while the connection thread opens or closes `pipe`. Taken before `m`, never
    // after it.
    std::mutex writeMutex;
    HANDLE pipe = INVALID_HANDLE_VALUE;
    uint32_t nextId = 1;

    std::atomic<ULONGLONG> lastTraffic{0};
    HANDLE waitEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE writeEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE dropEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);

    std::wstring pipeName;
    bool testPipe = false; // AIO_TIP_PIPE: never start the engine for it
    wire::Hello hello;

    Shared() = default;
    Shared(const Shared&) = delete;
    Shared& operator=(const Shared&) = delete;
    ~Shared() {
        if (pipe != INVALID_HANDLE_VALUE) CloseHandle(pipe);
        for (HANDLE h : {waitEvent, writeEvent, stopEvent, dropEvent}) {
            if (h) CloseHandle(h);
        }
    }

    bool Stopping() const { return WaitForSingleObject(stopEvent, 0) == WAIT_OBJECT_0; }

    // Under `m`.
    void PostLocked() {
        if (wnd && !postPending && PostMessageW(wnd, kMsgInbox, 0, 0)) postPending = true;
    }

    void Push(Inbound item) {
        std::lock_guard lock(m);
        item.seq = nextSeq++;
        inbox.push_back(std::move(item));
        PostLocked();
    }
};

namespace {

using Shared = PipeClient::Shared;

Io WriteMessage(HANDLE pipe, HANDLE event, const std::string& frame, DWORD timeoutMs) {
    OVERLAPPED ov = {};
    ov.hEvent = event;
    ResetEvent(event);
    DWORD n = 0;
    if (!WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()), nullptr, &ov)) {
        if (GetLastError() != ERROR_IO_PENDING) return Io::broken;
        if (WaitForSingleObject(event, timeoutMs) != WAIT_OBJECT_0) {
            CancelIoEx(pipe, &ov);
            GetOverlappedResult(pipe, &ov, &n, TRUE);
            return Io::timeout;
        }
    }
    if (!GetOverlappedResult(pipe, &ov, &n, FALSE) || n != frame.size()) return Io::broken;
    return Io::ok;
}

// One pipe message into `buffer[0, size)`, growing the buffer on ERROR_MORE_DATA up to the engine's limit (§2.2).
Io ReadMessage(Shared& s, HANDLE pipe, HANDLE event, std::string& buffer, size_t& size, DWORD timeoutMs) {
    constexpr size_t kMax = wire::kMaxEngineBody + 4;
    size = 0;
    if (buffer.size() < 64 * 1024) buffer.resize(64 * 1024);
    const ULONGLONG start = GetTickCount64();
    for (;;) {
        OVERLAPPED ov = {};
        ov.hEvent = event;
        ResetEvent(event);
        DWORD n = 0;
        const BOOL ok = ReadFile(pipe, buffer.data() + size, static_cast<DWORD>(buffer.size() - size), nullptr, &ov);
        const DWORD err = ok ? ERROR_SUCCESS : GetLastError();
        if (!ok && err != ERROR_IO_PENDING && err != ERROR_MORE_DATA) return Io::broken;
        if (err == ERROR_IO_PENDING) {
            DWORD timeout = INFINITE;
            if (timeoutMs != INFINITE) {
                const ULONGLONG elapsed = GetTickCount64() - start;
                timeout = elapsed >= timeoutMs ? 0 : static_cast<DWORD>(timeoutMs - elapsed);
            }
            HANDLE waits[] = {event, s.stopEvent, s.dropEvent};
            const DWORD w = WaitForMultipleObjects(3, waits, FALSE, timeout);
            if (w != WAIT_OBJECT_0) {
                CancelIoEx(pipe, &ov);
                GetOverlappedResult(pipe, &ov, &n, TRUE);
                if (w == WAIT_OBJECT_0 + 1) return Io::stopped;
                if (w == WAIT_OBJECT_0 + 2) return Io::dropped;
                if (w == WAIT_TIMEOUT) return Io::timeout;
                return Io::broken;
            }
        }
        if (GetOverlappedResult(pipe, &ov, &n, FALSE)) {
            size += n;
            return Io::ok;
        }
        if (GetLastError() != ERROR_MORE_DATA) return Io::broken;
        size += n;
        if (buffer.size() >= kMax) return Io::tooLarge;
        buffer.resize(std::min(buffer.size() * 2, kMax));
    }
}

HANDLE OpenPipe(Shared& s, DWORD* error) {
    *error = 0;
    for (int tries = 0; tries < 3 && !s.Stopping(); ++tries) {
        // Identification only: the server may learn who we are but never act as us.
        HANDLE h = CreateFileW(s.pipeName.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                               FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
        if (h != INVALID_HANDLE_VALUE) return h;
        *error = GetLastError();
        if (*error != ERROR_PIPE_BUSY) break;
        WaitNamedPipeW(s.pipeName.c_str(), 100); // §2.1
    }
    return INVALID_HANDLE_VALUE;
}

// §2.5: on ERROR_FILE_NOT_FOUND, a DLL in a medium-integrity, non-AppContainer process starts the engine from the path
// in HKLM\Software\AllInOneIME, value Engine, unless its single-instance mutex shows it running or starting.
void MaybeStartEngine(ULONGLONG& lastStart) {
    const auto& me = CurrentProcess();
    if (me.integrity != SECURITY_MANDATORY_MEDIUM_RID || me.appContainer) return;
    const ULONGLONG now = GetTickCount64();
    if (lastStart && now - lastStart < 10000) return;
    if (HANDLE mutex = OpenMutexW(SYNCHRONIZE, FALSE, EngineMutexName(me.userSid).c_str())) {
        CloseHandle(mutex);
        return;
    }
    wchar_t path[MAX_PATH] = {};
    DWORD size = sizeof path;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, L"Software\\AllInOneIME", L"Engine",
                     RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, path,
                     &size) != ERROR_SUCCESS ||
        !path[0]) {
        return;
    }
    lastStart = now;
    std::wstring command = L"\"" + std::wstring(path) + L"\"";
    STARTUPINFOW si = {sizeof si};
    PROCESS_INFORMATION pi = {};
    DWORD flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT;
    BOOL started = CreateProcessW(path, command.data(), nullptr, nullptr, FALSE, flags | CREATE_BREAKAWAY_FROM_JOB,
                                  nullptr, nullptr, &si, &pi);
    if (!started) started = CreateProcessW(path, command.data(), nullptr, nullptr, FALSE, flags, nullptr, nullptr, &si, &pi);
    if (started) {
        Log("started the engine, pid %lu", pi.dwProcessId);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    } else {
        Log("couldn't start the engine: error %lu", GetLastError());
    }
}

void ClosePipe(Shared& s) {
    std::lock_guard w(s.writeMutex);
    if (s.pipe != INVALID_HANDLE_VALUE) {
        CloseHandle(s.pipe);
        s.pipe = INVALID_HANDLE_VALUE;
    }
}

// Hands a frame to whoever wants it: the waiting request, or the TSF thread's queue.
void Route(Shared& s, uint64_t generation, wire::EngineMessage&& message) {
    std::lock_guard lock(s.m);
    const uint64_t seq = s.nextSeq++;
    if (message.re && s.waitId && *message.re == s.waitId && !s.waitDone) {
        s.waitResponse = std::move(message);
        s.waitSeq = seq;
        s.waitDone = true;
        SetEvent(s.waitEvent);
        return;
    }
    Inbound item;
    item.kind = Inbound::Kind::frame;
    item.generation = generation;
    item.seq = seq;
    item.message = std::move(message);
    s.inbox.push_back(std::move(item));
    s.PostLocked();
}

// hello and welcome (§2.4). False if this attempt got no welcome; `unsupported` if there is no common version.
bool Handshake(Shared& s, HANDLE pipe, HANDLE readEvent, std::string& buffer, wire::Welcome& welcome,
               bool& unsupported) {
    unsupported = false;
    std::string frame;
    {
        std::lock_guard w(s.writeMutex);
        s.nextId = 1;
        wire::Hello hello = s.hello;
        hello.id = s.nextId++;
        frame = wire::Frame(wire::Encode(hello));
        if (WriteMessage(pipe, s.writeEvent, frame, kHandshakeTimeoutMs) != Io::ok) return false;
    }
    size_t size = 0;
    const Io r = ReadMessage(s, pipe, readEvent, buffer, size, kHandshakeTimeoutMs);
    if (r != Io::ok) {
        Log("handshake: %s", IoName(r));
        return false;
    }
    std::string_view body;
    wire::EngineMessage message;
    if (!wire::Unframe(std::string_view(buffer.data(), size), body) ||
        wire::Decode(body, message) != wire::DecodeError::none) {
        Log("handshake: a bad frame");
        return false;
    }
    if (message.type == wire::EngineType::error) {
        Log("handshake: error %s", message.code.c_str());
        unsupported = message.code == "unsupportedVersion";
        return false;
    }
    if (message.type != wire::EngineType::welcome || message.re.value_or(0) != 1) {
        Log("handshake: no welcome");
        return false;
    }
    if (message.welcome.version != wire::kVersion) {
        Log("handshake: version %d", message.welcome.version);
        unsupported = true;
        return false;
    }
    welcome = message.welcome;
    return true;
}

void Run(Shared& s) {
    HANDLE readEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!readEvent) return;
    std::string buffer;
    size_t attempt = 0;
    ULONGLONG lastEngineStart = 0;
    ULONG refusedPid = 0; // §2.4: after unsupportedVersion, passive until a different engine
    DWORD lastError = MAXDWORD;

    while (!s.Stopping()) {
        DWORD delay = kBackoffMs[std::min(attempt, kLastBackoff)];
        {
            std::lock_guard lock(s.m);
            if (s.retryAfterMs) {
                delay = s.retryAfterMs;
                s.retryAfterMs = 0;
            }
        }
        if (delay && WaitForSingleObject(s.stopEvent, delay) == WAIT_OBJECT_0) break;
        if (s.Stopping()) break;
        ++attempt;

        DWORD error = 0;
        HANDLE pipe = OpenPipe(s, &error);
        if (pipe == INVALID_HANDLE_VALUE) {
            if (error != lastError) Log("connect: error %lu", error);
            lastError = error;
            if (error == ERROR_FILE_NOT_FOUND && !s.testPipe) MaybeStartEngine(lastEngineStart);
            continue;
        }
        lastError = MAXDWORD;
        const char* why = "";
        if (!VerifyServer(pipe, &why)) {
            Log("server check failed: %s; passive", why);
            CloseHandle(pipe);
            attempt = kLastBackoff;
            continue;
        }
        ULONG serverPid = 0;
        GetNamedPipeServerProcessId(pipe, &serverPid);
        if (refusedPid && serverPid == refusedPid) {
            CloseHandle(pipe);
            attempt = kLastBackoff;
            continue;
        }
        DWORD mode = PIPE_READMODE_MESSAGE;
        if (!SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)) {
            Log("connect: message mode failed, error %lu", GetLastError());
            CloseHandle(pipe);
            continue;
        }
        {
            std::lock_guard w(s.writeMutex);
            s.pipe = pipe;
        }

        wire::Welcome welcome;
        bool unsupported = false;
        if (!Handshake(s, pipe, readEvent, buffer, welcome, unsupported)) {
            ClosePipe(s);
            if (unsupported) {
                refusedPid = serverPid;
                attempt = kLastBackoff;
            }
            continue;
        }
        refusedPid = 0;
        attempt = 0;
        uint64_t generation = 0;
        {
            std::lock_guard lock(s.m);
            generation = ++s.generation;
            s.connected = true;
            ResetEvent(s.dropEvent);
            Inbound item;
            item.kind = Inbound::Kind::connected;
            item.generation = generation;
            item.seq = s.nextSeq++;
            item.message.type = wire::EngineType::welcome;
            item.message.welcome = welcome;
            s.inbox.push_back(std::move(item));
            s.PostLocked();
        }
        s.lastTraffic = GetTickCount64();
        Log("connected: engine pid %lu, generation %llu", welcome.enginePid, generation);

        const char* lost = "";
        for (;;) {
            size_t size = 0;
            const Io r = ReadMessage(s, pipe, readEvent, buffer, size, INFINITE);
            if (r != Io::ok) {
                lost = IoName(r);
                break;
            }
            s.lastTraffic = GetTickCount64();
            std::string_view body;
            if (!wire::Unframe(std::string_view(buffer.data(), size), body)) {
                lost = "badFrame (length)";
                break;
            }
            wire::EngineMessage message;
            const auto e = wire::Decode(body, message);
            if (e == wire::DecodeError::badFrame) {
                lost = "badFrame";
                break;
            }
            if (e == wire::DecodeError::badMessage) {
                Log("badMessage: type %s, %zu bytes", message.typeName.c_str(), body.size());
                if (!message.re) continue;
                // An answer the TSF thread may be waiting for: an error, so it passes the key (§3).
                wire::EngineMessage asError;
                asError.type = wire::EngineType::error;
                asError.typeName = "error";
                asError.code = "badMessage";
                asError.re = message.re;
                message = std::move(asError);
            }
            if (message.type == wire::EngineType::bye) {
                std::lock_guard lock(s.m);
                s.retryAfterMs = message.retryMs.value_or(0);
                lost = "bye";
                break;
            }
            Route(s, generation, std::move(message));
        }

        ClosePipe(s);
        {
            std::lock_guard lock(s.m);
            s.connected = false;
            if (s.waitId && !s.waitDone) {
                s.waitFailed = true;
                SetEvent(s.waitEvent);
            }
            Inbound item;
            item.kind = Inbound::Kind::disconnected;
            item.generation = generation;
            item.seq = s.nextSeq++;
            s.inbox.push_back(std::move(item));
            s.PostLocked();
        }
        Log("disconnected: %s", lost);
    }
    CloseHandle(readEvent);
}

DWORD WINAPI ThreadProc(void* param) {
    auto* boxed = static_cast<std::shared_ptr<Shared>*>(param);
    {
        std::shared_ptr<Shared> shared = std::move(*boxed);
        delete boxed;
        try {
            Run(*shared);
        } catch (...) {
            Log("exception on the connection thread");
        }
    }
    // Drop the module reference Start took, and exit. In a test exe there was none.
    if (g_module) FreeLibraryAndExitThread(g_module, 0);
    return 0;
}

} // namespace

PipeClient::PipeClient(PipeEvents* events) noexcept : events_(events) {}

PipeClient::~PipeClient() {
    Stop();
}

bool PipeClient::Start() {
    if (shared_) return true;
    const char* why = "";
    if (!MayConnect(&why)) {
        Log("passive: %s", why);
        return false;
    }
    auto shared = std::make_shared<Shared>();
    if (!shared->waitEvent || !shared->writeEvent || !shared->stopEvent || !shared->dropEvent) return false;
    const auto& me = CurrentProcess();
    shared->pipeName = PipeName(me.userSid);
    // A test points its own process's DLL at its own pipe (§2.1's name plus a suffix), so a fake engine never meets the
    // DLLs in the user's other apps. Only a name that extends the real one is taken, and the server check still holds.
    wchar_t over[256] = {};
    const DWORD overLength = GetEnvironmentVariableW(L"AIO_TIP_PIPE", over, static_cast<DWORD>(std::size(over)));
    if (overLength > shared->pipeName.size() && overLength < std::size(over) &&
        wcsncmp(over, shared->pipeName.c_str(), shared->pipeName.size()) == 0) {
        shared->pipeName = over;
        shared->testPipe = true;
        Log("a test pipe (%lu characters)", overLength);
    }
    shared->hello.client = kClientName;
    shared->hello.arch = kArch;
    shared->hello.pid = GetCurrentProcessId();
    shared->hello.tid = GetCurrentThreadId();
    shared->hello.capabilities = {"allowForeground"};

    {
        std::lock_guard lock(g_classMutex);
        if (g_classUsers == 0) {
            WNDCLASSEXW wc = {sizeof wc};
            wc.lpfnWndProc = WindowProc;
            wc.hInstance = g_module;
            wc.lpszClassName = kWindowClass;
            if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
        }
        ++g_classUsers;
    }
    wnd_ = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, g_module, nullptr);
    if (!wnd_) {
        std::lock_guard lock(g_classMutex);
        if (--g_classUsers == 0) UnregisterClassW(kWindowClass, g_module);
        return false;
    }
    SetWindowLongPtrW(wnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    SetTimer(wnd_, kTimerKeepalive, 1000, nullptr);
    shared->wnd = wnd_;
    shared_ = shared;

    // Keep the DLL loaded for the connection thread's lifetime (it may outlive Stop's short wait). The thread drops
    // this reference with FreeLibraryAndExitThread. In a test exe (g_module null) there is nothing to hold.
    HMODULE held = nullptr;
    if (g_module) {
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, reinterpret_cast<LPCWSTR>(&ThreadProc), &held);
    }
    auto* boxed = new std::shared_ptr<Shared>(shared);
    thread_ = CreateThread(nullptr, 0, ThreadProc, boxed, 0, nullptr);
    if (!thread_) {
        delete boxed;
        if (held) FreeLibrary(held);
        Stop();
        return false;
    }
    Log("pipe client started");
    return true;
}

void PipeClient::Stop() noexcept {
    if (wnd_) {
        if (shared_) {
            std::lock_guard lock(shared_->m);
            shared_->wnd = nullptr;
        }
        DestroyWindow(wnd_);
        wnd_ = nullptr;
        std::lock_guard lock(g_classMutex);
        if (--g_classUsers == 0) UnregisterClassW(kWindowClass, g_module);
    }
    if (shared_) {
        SetEvent(shared_->stopEvent);
        {
            std::lock_guard lock(shared_->m);
            shared_->connected = false;
        }
        shared_.reset();
    }
    if (thread_) {
        // The thread notices the stop at once unless it is inside a short wait (≤ 100 ms, a handshake ≤ 2 s). It keeps
        // the DLL (a module reference) and its state (the shared_ptr) alive by itself, so the TSF thread doesn't wait.
        CloseHandle(thread_);
        thread_ = nullptr;
    }
    ready_ = false;
}

bool PipeClient::Write(const Builder& build, DWORD timeoutMs, WriteKind kind, uint32_t* idOut) noexcept {
    if (!shared_ || !ready_) return false;
    Shared& s = *shared_;
    Io r = Io::broken;
    try {
        // Only the connection thread contends for it, while it sets a connection up (the hello, ≤ 2 s) or tears one
        // down; a frame for this connection can't go then anyway, and the TSF thread must not wait for it.
        std::unique_lock w(s.writeMutex, std::try_to_lock);
        if (!w.owns_lock()) return false;
        {
            std::lock_guard lock(s.m);
            if (!s.connected || s.generation != generation_) return false;
        }
        if (s.pipe == INVALID_HANDLE_VALUE) return false;
        const uint32_t id = s.nextId;
        const std::string body = build(id);
        if (body.empty() || body.size() > wire::kMaxClientBody) {
            Log("not sent: a frame of %zu bytes", body.size());
            return false;
        }
        ++s.nextId;
        if (idOut) *idOut = id;
        if (kind == WriteKind::request) {
            std::lock_guard lock(s.m);
            s.waitId = id;
            s.waitDone = false;
            s.waitFailed = false;
            ResetEvent(s.waitEvent);
        }
        r = WriteMessage(s.pipe, s.writeEvent, wire::Frame(body), timeoutMs);
    } catch (...) {
        r = Io::broken;
    }
    if (r != Io::ok) {
        if (kind == WriteKind::request) {
            std::lock_guard lock(s.m);
            s.waitId = 0;
        }
        Drop(r == Io::timeout ? "a write timed out" : "a write failed");
        return false;
    }
    s.lastTraffic = GetTickCount64();
    return true;
}

bool PipeClient::Send(const Builder& build) noexcept {
    return Write(build, kNotificationWriteTimeoutMs, WriteKind::notification, nullptr);
}

PipeClient::Outcome PipeClient::Request(const Builder& build, DWORD budgetMs, wire::EngineMessage& response,
                                        uint32_t* idOut) noexcept {
    const ULONGLONG start = GetTickCount64();
    uint32_t id = 0;
    if (!Write(build, budgetMs, WriteKind::request, &id)) return Outcome::failed;
    if (idOut) *idOut = id;
    Shared& s = *shared_;
    const ULONGLONG elapsed = GetTickCount64() - start;
    WaitForSingleObject(s.waitEvent, elapsed >= budgetMs ? 0 : static_cast<DWORD>(budgetMs - elapsed));
    std::lock_guard lock(s.m);
    s.waitId = 0; // a late answer goes to the queue, where nobody wants it (§5.4: discarded)
    if (s.waitDone) {
        s.waitDone = false;
        try {
            response = std::move(s.waitResponse);
        } catch (...) {
            return Outcome::failed;
        }
        lastResponseSeq_ = s.waitSeq;
        return Outcome::response;
    }
    return s.waitFailed ? Outcome::failed : Outcome::timeout;
}

uint32_t PipeClient::RequestAsync(const Builder& build) noexcept {
    uint32_t id = 0;
    return Write(build, kNotificationWriteTimeoutMs, WriteKind::asyncRequest, &id) ? id : 0;
}

std::vector<wire::EngineMessage> PipeClient::TakeEarlier(
    const std::function<bool(const wire::EngineMessage&)>& pick) noexcept {
    std::vector<wire::EngineMessage> taken;
    if (!shared_) return taken;
    try {
        std::lock_guard lock(shared_->m);
        auto& inbox = shared_->inbox;
        for (auto it = inbox.begin(); it != inbox.end();) {
            if (it->kind == Inbound::Kind::frame && it->seq < lastResponseSeq_ && it->generation == generation_ &&
                pick(it->message)) {
                taken.push_back(std::move(it->message));
                it = inbox.erase(it);
            } else {
                ++it;
            }
        }
    } catch (...) {
    }
    return taken;
}

bool PipeClient::AnyEarlier(const std::function<bool(const wire::EngineMessage&)>& pick) const noexcept {
    if (!shared_) return false;
    try {
        std::lock_guard lock(shared_->m);
        for (const auto& item : shared_->inbox) {
            if (item.kind == Inbound::Kind::frame && item.seq < lastResponseSeq_ && item.generation == generation_ &&
                pick(item.message)) {
                return true;
            }
        }
    } catch (...) {
    }
    return false;
}

void PipeClient::Drop(const char* why) noexcept {
    if (!shared_) return;
    std::lock_guard lock(shared_->m);
    if (shared_->connected && shared_->generation == generation_) {
        Log("dropping the connection: %s", why);
        SetEvent(shared_->dropEvent);
    }
}

void PipeClient::StartTimer(UINT_PTR id, UINT ms) noexcept {
    if (wnd_) SetTimer(wnd_, id, ms, nullptr);
}

void PipeClient::StopTimer(UINT_PTR id) noexcept {
    if (wnd_) KillTimer(wnd_, id);
}

void PipeClient::Drain() noexcept {
    for (;;) {
        std::deque<Inbound> items;
        if (!shared_) return;
        {
            std::lock_guard lock(shared_->m);
            shared_->postPending = false;
            items.swap(shared_->inbox);
        }
        if (items.empty()) return;
        for (auto& item : items) {
            NoThrow("Drain", [&] {
                switch (item.kind) {
                case Inbound::Kind::connected:
                    ready_ = true;
                    generation_ = item.generation;
                    welcome_ = item.message.welcome;
                    pingId_ = 0;
                    events_->OnPipeConnected(welcome_);
                    break;
                case Inbound::Kind::disconnected:
                    if (item.generation == generation_ && ready_) {
                        ready_ = false;
                        pingId_ = 0;
                        events_->OnPipeDisconnected();
                    }
                    break;
                case Inbound::Kind::frame:
                    if (item.generation != generation_ || !ready_) break;
                    if (item.message.type == wire::EngineType::pong && pingId_ && item.message.re == pingId_) {
                        pingId_ = 0;
                        break;
                    }
                    events_->OnPipeMessage(item.message);
                    break;
                }
            });
            if (!shared_) return; // a handler stopped the client
        }
    }
}

void PipeClient::Keepalive() noexcept {
    if (!shared_ || !ready_) return;
    const ULONGLONG now = GetTickCount64();
    if (pingId_) {
        if (now > pingDeadline_) {
            pingId_ = 0;
            Drop("no pong");
        }
        return;
    }
    if (!focused_ || now - shared_->lastTraffic < kKeepaliveIdleMs) return;
    const uint32_t id = RequestAsync([](uint32_t id) { return wire::Encode(wire::Ping{id}); });
    if (id) {
        pingId_ = id;
        pingDeadline_ = now + kPongTimeoutMs;
    }
}

LRESULT CALLBACK PipeClient::WindowProc(HWND wnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto* self = reinterpret_cast<PipeClient*>(GetWindowLongPtrW(wnd, GWLP_USERDATA));
    if (self) {
        if (msg == kMsgInbox) {
            self->Drain();
            return 0;
        }
        if (msg == WM_TIMER) {
            if (wParam == kTimerKeepalive) {
                self->Keepalive();
            } else {
                KillTimer(wnd, wParam);
                NoThrow("OnPipeTimer", [&] { self->events_->OnPipeTimer(wParam); });
            }
            return 0;
        }
    }
    return DefWindowProcW(wnd, msg, wParam, lParam);
}

} // namespace aio
