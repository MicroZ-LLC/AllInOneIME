// A fake engine for the tests: it creates the pipe exactly as §2.1 says (the same name, flags and security descriptor
// the real engine uses) and replays a golden transcript — sending the `<` frames and checking the `>` frames the DLL
// sends against the golden, in order.
//
// It runs on its own thread (Start/Join) so the DLL's TSF thread can drive keys at the same time. The result records
// every mismatch and the frames it saw, for the report.

#pragma once

#include <windows.h>

#include <atomic>
#include <string>
#include <thread>
#include <vector>

#include "Transcript.h"

namespace aio::test {

struct EngineResult {
    bool ok = false;
    std::string summary;              // "7/7 frames matched" or the first failure
    std::vector<std::string> notes;   // per-step detail
    int matched = 0;
    int expected = 0;
};

class FakeEngine {
public:
    // `pipeName` empty → the real §2.1 name for this user. `userSid` empty → the current user's.
    FakeEngine(Transcript transcript, std::wstring pipeName = {}, std::wstring userSid = {});
    ~FakeEngine();

    void Start();                     // creates the pipe and begins replaying on a background thread
    void Join();                      // waits for the replay to finish
    void Stop();                      // asks the replay to stop early
    bool PipeReady() const { return pipeReady_.load(); }
    const EngineResult& Result() const { return result_; }

    static std::wstring RealPipeName(const std::wstring& userSid);
    static std::wstring CurrentUserSid();

private:
    void Run();
    HANDLE CreateInstance(bool first);
    bool AcceptClient(HANDLE pipe);
    bool VerifyClient(HANDLE pipe); // §2.1's client check, as the engine does it
    bool ReadFrame(HANDLE pipe, std::string& body, DWORD timeoutMs);
    bool SendFrame(HANDLE pipe, const nlohmann::json& body);
    void Note(const std::string& s);

    Transcript transcript_;
    std::wstring pipeName_;
    std::wstring userSid_;
    std::thread thread_;
    std::atomic<bool> pipeReady_{false};
    std::atomic<bool> stop_{false};
    HANDLE pipe_ = INVALID_HANDLE_VALUE;
    HANDLE readEvent_ = nullptr;
    HANDLE writeEvent_ = nullptr;
    EngineResult result_;
};

} // namespace aio::test
